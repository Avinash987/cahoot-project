USE StackOverflow2013;
GO

/* =========================================================
   Task 1 - Search Query
   Includes:
   1) Supporting permanent indexes for title-prefix search
   2) Page query used by the MVC application

   Sample inputs below can be changed for ad hoc testing.
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

DECLARE @Query NVARCHAR(100) = N'java';
DECLARE @OffsetRows INT = 0;
DECLARE @PageSizeRows INT = 10;

DECLARE @SearchPrefix NVARCHAR(110) = @Query + '%';
DECLARE @Offset INT = @OffsetRows;
DECLARE @PageSize INT = @PageSizeRows;

SELECT TOP (200)
    q.Id,
    q.Title,
    q.Body,
    q.OwnerUserId,
    q.CreationDate
INTO #CandidateQuestions
FROM dbo.Posts q
WHERE q.PostTypeId = 1
AND q.Title LIKE @SearchPrefix
ORDER BY q.CreationDate DESC
OPTION (RECOMPILE);

CREATE CLUSTERED INDEX IX_CandidateQuestions_Id
ON #CandidateQuestions (Id);

CREATE NONCLUSTERED INDEX IX_CandidateQuestions_OwnerUserId
ON #CandidateQuestions (OwnerUserId);

WITH CandidateOwners AS (
    SELECT DISTINCT OwnerUserId AS UserId
    FROM #CandidateQuestions
    WHERE OwnerUserId IS NOT NULL
),
AnswerCounts AS (
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers
    FROM dbo.Posts p
    INNER JOIN #CandidateQuestions cq
        ON cq.Id = p.ParentId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
VoteTotals AS (
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM dbo.Votes v
    INNER JOIN #CandidateQuestions cq
        ON cq.Id = v.PostId
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
BadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges
    FROM dbo.Badges b
    WHERE EXISTS (
        SELECT 1
        FROM CandidateOwners co
        WHERE co.UserId = b.UserId
    )
    GROUP BY b.UserId
)
SELECT
    cq.Id AS QuestionId,
    cq.Title,
    LEFT(cq.Body, 1000) AS Snippet,
    ISNULL(vt.Upvotes, 0) - ISNULL(vt.Downvotes, 0) AS TotalVotes,
    ISNULL(ac.TotalAnswers, 0) AS TotalAnswers,
    ISNULL(u.DisplayName, 'Unknown User') AS AskedBy,
    u.Reputation,
    ISNULL(bc.TotalBadges, 0) AS TotalBadges
FROM #CandidateQuestions cq
LEFT JOIN dbo.Users u
    ON u.Id = cq.OwnerUserId
LEFT JOIN AnswerCounts ac
    ON ac.QuestionId = cq.Id
LEFT JOIN VoteTotals vt
    ON vt.PostId = cq.Id
LEFT JOIN BadgeCounts bc
    ON bc.UserId = u.Id
ORDER BY
    ISNULL(vt.Upvotes, 0) - ISNULL(vt.Downvotes, 0) DESC,
    cq.CreationDate DESC
OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;
