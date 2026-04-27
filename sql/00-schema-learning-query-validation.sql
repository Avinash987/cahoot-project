/*
===========================================================================
Schema Learning, Quick Checks, and Query Scratch Work
===========================================================================

This file is not one of my final polished answers. I used queries like these
while learning the StackOverflow database and checking that my final Task 1,
Task 2, and Task 3 queries were based on the right columns and relationships.

I kept this script in the repo as proof of work / evidence. Some queries are
just quick checks, and some are early versions of the final query shapes.

Things I checked here:
- Posts.PostTypeId = 1 is a question
- Posts.PostTypeId = 2 is an answer
- Answer posts point back to questions through Posts.ParentId
- Questions point to accepted answers through Posts.AcceptedAnswerId
- Votes.PostId links votes to posts
- VoteTypeId = 2 is an upvote
- VoteTypeId = 3 is a downvote

The final task queries are in:
- sql/01-task-2.sql
- sql/02-task-3.sql
- sql/03-search-query.sql
===========================================================================
*/

USE StackOverflow2013;
GO

/* Quick look at the main tables. */

SELECT TOP 20 * FROM dbo.Posts;
SELECT TOP 20 * FROM dbo.Users;
SELECT TOP 20 * FROM dbo.Votes;
SELECT TOP 20 * FROM dbo.Badges;
GO


/* Check the columns and data types before writing joins. */

SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('Posts', 'Users', 'Votes', 'Badges')
ORDER BY TABLE_NAME, ORDINAL_POSITION;
GO


/* Check post type values and rough row counts. */

SELECT
    PostTypeId,
    COUNT(*) AS Cnt
FROM dbo.Posts
GROUP BY PostTypeId
ORDER BY PostTypeId;
GO


/* Check answer -> question relationship using ParentId. */

SELECT TOP 20
    a.Id AS AnswerId,
    a.ParentId AS QuestionId,
    q.Title AS QuestionTitle
FROM dbo.Posts a
JOIN dbo.Posts q
    ON q.Id = a.ParentId
WHERE a.PostTypeId = 2
  AND q.PostTypeId = 1;
GO


/* Check question -> accepted answer relationship. */

SELECT TOP 20
    q.Id AS QuestionId,
    q.AcceptedAnswerId,
    a.Id AS AcceptedAnswerPostId,
    a.ParentId AS AnswerBelongsToQuestion
FROM dbo.Posts q
JOIN dbo.Posts a
    ON a.Id = q.AcceptedAnswerId
WHERE q.PostTypeId = 1
  AND q.AcceptedAnswerId IS NOT NULL;
GO


/* Check vote type distribution. I used this to confirm upvote/downvote ids. */

SELECT
    VoteTypeId,
    COUNT(*) AS Cnt
FROM dbo.Votes
GROUP BY VoteTypeId
ORDER BY VoteTypeId;
GO


/* First weekly posts check for Task 3. */

SELECT TOP 20
    DATEADD(WEEK, DATEDIFF(WEEK, 0, CreationDate), 0) AS WeekStart,
    SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
FROM dbo.Posts
WHERE PostTypeId IN (1, 2)
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, CreationDate), 0)
ORDER BY WeekStart DESC;
GO


/* Accepted answer count by the accepted answer post's week. */

SELECT TOP 20
    DATEADD(WEEK, DATEDIFF(WEEK, 0, a.CreationDate), 0) AS WeekStart,
    COUNT(*) AS AcceptedAnswerCount
FROM dbo.Posts q
JOIN dbo.Posts a
    ON a.Id = q.AcceptedAnswerId
WHERE q.PostTypeId = 1
  AND q.AcceptedAnswerId IS NOT NULL
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, a.CreationDate), 0)
ORDER BY WeekStart DESC;
GO


/* Weekly votes check for Task 3. */

SELECT TOP 20
    DATEADD(WEEK, DATEDIFF(WEEK, 0, CreationDate), 0) AS WeekStart,
    COUNT(*) AS VoteCount
FROM dbo.Votes
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, CreationDate), 0)
ORDER BY WeekStart DESC;
GO


/* Weekly new users check. */

SELECT TOP 20
    DATEADD(WEEK, DATEDIFF(WEEK, 0, CreationDate), 0) AS WeekStart,
    COUNT(*) AS NewUserCount
FROM dbo.Users
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, CreationDate), 0)
ORDER BY WeekStart DESC;
GO


/* Active users test. I defined active as posted or voted in that week. */

WITH ActiveUsers AS
(
    SELECT
        DATEADD(WEEK, DATEDIFF(WEEK, 0, p.CreationDate), 0) AS WeekStart,
        p.OwnerUserId AS UserId
    FROM dbo.Posts p
    WHERE p.OwnerUserId IS NOT NULL

    UNION

    SELECT
        DATEADD(WEEK, DATEDIFF(WEEK, 0, v.CreationDate), 0) AS WeekStart,
        v.UserId AS UserId
    FROM dbo.Votes v
    WHERE v.UserId IS NOT NULL
)
SELECT TOP 20
    WeekStart,
    COUNT(DISTINCT UserId) AS ActiveUserCount
FROM ActiveUsers
GROUP BY WeekStart
ORDER BY WeekStart DESC;
GO


/* Quick Task 2 shape before polishing the final file. */

WITH VoteTotals AS
(
    SELECT
        PostId,
        SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM dbo.Votes
    WHERE VoteTypeId IN (2, 3)
    GROUP BY PostId
)
SELECT
    CASE p.PostTypeId
        WHEN 1 THEN 'Question'
        WHEN 2 THEN 'Answer'
    END AS PostType,
    DATENAME(WEEKDAY, p.CreationDate) AS DayOfWeek,
    COUNT(*) AS TotalPosts,
    SUM(ISNULL(vt.Upvotes, 0)) AS TotalUpvotes,
    SUM(ISNULL(vt.Downvotes, 0)) AS TotalDownvotes,
    CAST(SUM(ISNULL(vt.Upvotes, 0)) AS DECIMAL(18, 4))
        / NULLIF(SUM(ISNULL(vt.Downvotes, 0)), 0) AS UpvoteDownvoteRatio
FROM dbo.Posts p
LEFT JOIN VoteTotals vt
    ON vt.PostId = p.Id
WHERE p.PostTypeId IN (1, 2)
GROUP BY
    p.PostTypeId,
    DATENAME(WEEKDAY, p.CreationDate),
    DATEPART(WEEKDAY, p.CreationDate)
ORDER BY UpvoteDownvoteRatio DESC;
GO


/*
Search scratch query for Task 1.

This is meant to show the final practical direction, not full-text search.
Full-Text Search was not installed locally, and broad Body LIKE searches were
too slow, so I used bounded candidates from title/tag matches and then enriched
only those rows.
*/

DECLARE @Query NVARCHAR(100) = N'java';
DECLARE @Prefix NVARCHAR(110) = @Query + N'%';
DECLARE @TagPrefix NVARCHAR(110) = N'<' + @Query + N'%';
DECLARE @Offset INT = 0;
DECLARE @PageSize INT = 10;

IF OBJECT_ID('tempdb..#Candidates') IS NOT NULL DROP TABLE #Candidates;

CREATE TABLE #Candidates
(
    QuestionId INT NOT NULL,
    SourcePostId INT NOT NULL,
    Title NVARCHAR(250) NULL,
    Body NVARCHAR(MAX) NULL,
    OwnerUserId INT NULL,
    CreationDate DATETIME NOT NULL,
    ResultType NVARCHAR(20) NOT NULL,
    MatchReason NVARCHAR(80) NOT NULL,
    RelevanceRank INT NOT NULL
);

INSERT INTO #Candidates
(
    QuestionId,
    SourcePostId,
    Title,
    Body,
    OwnerUserId,
    CreationDate,
    ResultType,
    MatchReason,
    RelevanceRank
)
SELECT TOP (120)
    q.Id,
    q.Id,
    q.Title,
    q.Body,
    q.OwnerUserId,
    q.CreationDate,
    N'Question',
    N'Title prefix match',
    1
FROM dbo.Posts q
WHERE q.PostTypeId = 1
  AND q.Title LIKE @Prefix
ORDER BY q.CreationDate DESC;

INSERT INTO #Candidates
(
    QuestionId,
    SourcePostId,
    Title,
    Body,
    OwnerUserId,
    CreationDate,
    ResultType,
    MatchReason,
    RelevanceRank
)
SELECT TOP (120)
    q.Id,
    q.Id,
    q.Title,
    q.Body,
    q.OwnerUserId,
    q.CreationDate,
    N'Question',
    N'Tag match',
    2
FROM dbo.Posts q
WHERE q.PostTypeId = 1
  AND q.Tags LIKE @TagPrefix
ORDER BY q.CreationDate DESC;

INSERT INTO #Candidates
(
    QuestionId,
    SourcePostId,
    Title,
    Body,
    OwnerUserId,
    CreationDate,
    ResultType,
    MatchReason,
    RelevanceRank
)
SELECT TOP (120)
    q.Id,
    a.Id,
    q.Title,
    a.Body,
    q.OwnerUserId,
    a.CreationDate,
    N'Answer',
    N'Answer under matching question',
    3
FROM dbo.Posts q
JOIN dbo.Posts a
    ON a.ParentId = q.Id
WHERE q.PostTypeId = 1
  AND a.PostTypeId = 2
  AND (q.Title LIKE @Prefix OR q.Tags LIKE @TagPrefix)
ORDER BY a.CreationDate DESC;

WITH Deduped AS
(
    SELECT
        *,
        ROW_NUMBER() OVER
        (
            PARTITION BY QuestionId, SourcePostId
            ORDER BY RelevanceRank, CreationDate DESC
        ) AS RowNumber
    FROM #Candidates
),
Paged AS
(
    SELECT *
    FROM Deduped
    WHERE RowNumber = 1
    ORDER BY RelevanceRank, CreationDate DESC
    OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY
),
AnswerCounts AS
(
    SELECT
        p.ParentId AS QuestionId,
        COUNT(*) AS TotalAnswers
    FROM dbo.Posts p
    JOIN Paged pg
        ON pg.QuestionId = p.ParentId
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
VoteTotals AS
(
    SELECT
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
    FROM dbo.Votes v
    JOIN Paged pg
        ON pg.QuestionId = v.PostId
    WHERE v.VoteTypeId IN (2, 3)
    GROUP BY v.PostId
),
BadgeCounts AS
(
    SELECT
        b.UserId,
        COUNT(*) AS TotalBadges
    FROM dbo.Badges b
    JOIN Paged pg
        ON pg.OwnerUserId = b.UserId
    GROUP BY b.UserId
)
SELECT
    pg.QuestionId,
    pg.SourcePostId,
    pg.ResultType,
    pg.MatchReason,
    pg.Title,
    LEFT(REPLACE(REPLACE(REPLACE(pg.Body, CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' '), 140) AS Snippet,
    ISNULL(vt.Upvotes, 0) - ISNULL(vt.Downvotes, 0) AS TotalVotes,
    ISNULL(ac.TotalAnswers, 0) AS TotalAnswers,
    ISNULL(u.DisplayName, 'Unknown User') AS AskedBy,
    u.Reputation,
    ISNULL(bc.TotalBadges, 0) AS TotalBadges
FROM Paged pg
LEFT JOIN dbo.Users u
    ON u.Id = pg.OwnerUserId
LEFT JOIN AnswerCounts ac
    ON ac.QuestionId = pg.QuestionId
LEFT JOIN VoteTotals vt
    ON vt.PostId = pg.QuestionId
LEFT JOIN BadgeCounts bc
    ON bc.UserId = pg.OwnerUserId
ORDER BY
    pg.RelevanceRank,
    pg.CreationDate DESC;
GO
