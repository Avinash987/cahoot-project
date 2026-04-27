USE StackOverflow2013;
GO

/* =========================================================
   Task 1 - Search Query
   Includes:
   1) Supporting permanent indexes for practical local search
   2) Ranked question/tag/answer candidate query used by the MVC app

   Full-Text Search was not available in the local SQL Server
   environment, so this uses indexed prefix/tag matching instead.
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Posts_PostTypeId_Title'
        AND object_id = OBJECT_ID('dbo.Posts')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Posts_PostTypeId_Title
    ON dbo.Posts (PostTypeId, Title)
    INCLUDE (Id, OwnerUserId, CreationDate);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Posts_PostTypeId_Tags'
        AND object_id = OBJECT_ID('dbo.Posts')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Posts_PostTypeId_Tags
    ON dbo.Posts (PostTypeId, Tags)
    INCLUDE (Id, Title, OwnerUserId, CreationDate);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Posts_ParentId_PostTypeId'
        AND object_id = OBJECT_ID('dbo.Posts')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Posts_ParentId_PostTypeId
    ON dbo.Posts (ParentId, PostTypeId)
    INCLUDE (Id);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Votes_PostId_VoteTypeId'
        AND object_id = OBJECT_ID('dbo.Votes')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Votes_PostId_VoteTypeId
    ON dbo.Votes (PostId, VoteTypeId);
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_Badges_UserId'
        AND object_id = OBJECT_ID('dbo.Badges')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Badges_UserId
    ON dbo.Badges (UserId);
END
GO

DECLARE @Query NVARCHAR(100) = N'java 8';
DECLARE @SeedTerm NVARCHAR(100) = LEFT(@Query, CHARINDEX(N' ', @Query + N' ') - 1);
DECLARE @SearchPrefix NVARCHAR(110) = @Query + N'%';
DECLARE @TagPrefix NVARCHAR(110) = N'<' + @SeedTerm + N'>%';
DECLARE @Offset INT = 0;
DECLARE @PageSize INT = 10;

CREATE TABLE #RawCandidates
(
    QuestionId INT NOT NULL,
    SourcePostId INT NOT NULL,
    Title NVARCHAR(250) NULL,
    Body NVARCHAR(MAX) NULL,
    OwnerUserId INT NULL,
    CreationDate DATETIME NULL,
    RelevanceRank INT NOT NULL,
    ResultType NVARCHAR(20) NOT NULL,
    MatchReason NVARCHAR(80) NOT NULL
);

INSERT INTO #RawCandidates
SELECT TOP (200)
    q.Id AS QuestionId,
    q.Id AS SourcePostId,
    q.Title,
    q.Body,
    q.OwnerUserId,
    q.CreationDate,
    1 AS RelevanceRank,
    N'Question' AS ResultType,
    N'Title prefix match' AS MatchReason
FROM (
    SELECT TOP (200)
        titleMatch.Id,
        titleMatch.CreationDate
    FROM dbo.Posts titleMatch WITH (INDEX(IX_Posts_PostTypeId_Title))
    WHERE titleMatch.PostTypeId = 1
    AND titleMatch.Title LIKE @SearchPrefix
    ORDER BY titleMatch.CreationDate DESC
) matchedTitles
INNER JOIN dbo.Posts q
    ON q.Id = matchedTitles.Id
ORDER BY matchedTitles.CreationDate DESC;

INSERT INTO #RawCandidates
SELECT TOP (200)
    q.Id AS QuestionId,
    q.Id AS SourcePostId,
    q.Title,
    q.Body,
    q.OwnerUserId,
    q.CreationDate,
    2 AS RelevanceRank,
    N'Question' AS ResultType,
    N'Tag match' AS MatchReason
FROM (
    SELECT TOP (200)
        tagMatch.Id,
        tagMatch.CreationDate
    FROM dbo.Posts tagMatch WITH (INDEX(IX_Posts_PostTypeId_Tags))
    WHERE tagMatch.PostTypeId = 1
    AND tagMatch.Tags LIKE @TagPrefix
    ORDER BY tagMatch.CreationDate DESC
) matchedTags
INNER JOIN dbo.Posts q
    ON q.Id = matchedTags.Id
ORDER BY matchedTags.CreationDate DESC;

SELECT DISTINCT
    QuestionId,
    Title,
    OwnerUserId
INTO #MatchedQuestions
FROM #RawCandidates
WHERE ResultType = N'Question';

CREATE CLUSTERED INDEX IX_MatchedQuestions_QuestionId
ON #MatchedQuestions (QuestionId);

INSERT INTO #RawCandidates
SELECT TOP (100)
    qm.QuestionId,
    a.Id AS SourcePostId,
    qm.Title,
    a.Body,
    qm.OwnerUserId,
    a.CreationDate,
    3 AS RelevanceRank,
    N'Answer' AS ResultType,
    N'Answer under matching question' AS MatchReason
FROM #MatchedQuestions qm
INNER JOIN dbo.Posts a WITH (INDEX(IX_Posts_ParentId_PostTypeId))
    ON a.ParentId = qm.QuestionId
    AND a.PostTypeId = 2
ORDER BY a.CreationDate DESC;

WITH RankedCandidates AS (
    SELECT
        QuestionId,
        SourcePostId,
        Title,
        Body,
        OwnerUserId,
        CreationDate,
        RelevanceRank,
        ResultType,
        MatchReason,
        ROW_NUMBER() OVER (
            PARTITION BY SourcePostId
            ORDER BY RelevanceRank, CreationDate DESC
        ) AS RowNumber
    FROM #RawCandidates
)
SELECT
    QuestionId,
    SourcePostId,
    Title,
    Body,
    OwnerUserId,
    CreationDate,
    RelevanceRank,
    ResultType,
    MatchReason
INTO #PagedResults
FROM RankedCandidates
WHERE RowNumber = 1
ORDER BY
    RelevanceRank,
    CreationDate DESC
OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;

WITH CandidateOwners AS (
    SELECT DISTINCT OwnerUserId AS UserId
    FROM #PagedResults
    WHERE OwnerUserId IS NOT NULL
),
CandidateQuestions AS (
    SELECT DISTINCT QuestionId
    FROM #PagedResults
),
AnswerCounts AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers
    FROM dbo.Posts p WITH (INDEX(IX_Posts_ParentId_PostTypeId))
    INNER JOIN CandidateQuestions cq
        ON cq.QuestionId = p.ParentId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
VoteTotals AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
            - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalVotes
    FROM dbo.Votes v WITH (INDEX(IX_Votes_PostId_VoteTypeId))
    INNER JOIN #PagedResults pr
        ON pr.SourcePostId = v.PostId
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
BadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges
    FROM dbo.Badges b WITH (INDEX(IX_Badges_UserId))
    WHERE EXISTS (
        SELECT 1
        FROM CandidateOwners co
        WHERE co.UserId = b.UserId
    )
    GROUP BY b.UserId
)
SELECT
    pr.QuestionId,
    pr.SourcePostId,
    pr.Title,
    pr.ResultType,
    pr.MatchReason,
    LEFT(pr.Body, 1000) AS Snippet,
    ISNULL(vt.TotalVotes, 0) AS TotalVotes,
    ISNULL(ac.TotalAnswers, 0) AS TotalAnswers,
    ISNULL(u.DisplayName, 'Unknown User') AS AskedBy,
    u.Reputation,
    ISNULL(bc.TotalBadges, 0) AS TotalBadges
FROM #PagedResults pr
LEFT JOIN dbo.Users u
    ON u.Id = pr.OwnerUserId
LEFT JOIN AnswerCounts ac
    ON ac.QuestionId = pr.QuestionId
LEFT JOIN VoteTotals vt
    ON vt.PostId = pr.SourcePostId
LEFT JOIN BadgeCounts bc
    ON bc.UserId = u.Id
ORDER BY
    pr.RelevanceRank,
    pr.CreationDate DESC;
