DECLARE @Search NVARCHAR(100) = @Query;
DECLARE @Contains NVARCHAR(110) = '%' + @Search + '%';
DECLARE @Offset INT = @OffsetRows;
DECLARE @PageSize INT = @PageSizeRows;

WITH
    AnswerCounts
    AS
    (
        SELECT
            ParentId AS QuestionId,
            COUNT(*) AS TotalAnswers
        FROM dbo.Posts
        WHERE PostTypeId = 2
            AND ParentId IS NOT NULL
        GROUP BY ParentId
    ),
    VoteTotals
    AS
    (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
        FROM dbo.Votes
        WHERE VoteTypeId IN (2, 3)
        GROUP BY PostId
    ),
    BadgeCounts
    AS
    (
        SELECT
            UserId,
            COUNT(*) AS TotalBadges
        FROM dbo.Badges
        GROUP BY UserId
    )
SELECT
    q.Id AS QuestionId,
    q.Title,
    LEFT(
        REPLACE(REPLACE(REPLACE(q.Body, CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' '),
        140
    ) AS Snippet,
    ISNULL(vt.Upvotes, 0) - ISNULL(vt.Downvotes, 0) AS TotalVotes,
    ISNULL(ac.TotalAnswers, 0) AS TotalAnswers,
    ISNULL(u.DisplayName, 'Unknown User') AS AskedBy,
    u.Reputation,
    ISNULL(bc.TotalBadges, 0) AS TotalBadges
FROM dbo.Posts q
    LEFT JOIN dbo.Users u
    ON u.Id = q.OwnerUserId
    LEFT JOIN AnswerCounts ac
    ON ac.QuestionId = q.Id
    LEFT JOIN VoteTotals vt
    ON vt.PostId = q.Id
    LEFT JOIN BadgeCounts bc
    ON bc.UserId = u.Id
WHERE q.PostTypeId = 1
    AND (
       q.Title LIKE @Contains
    OR q.Body  LIKE @Contains
  )
ORDER BY
    CASE WHEN q.Title LIKE @Contains THEN 1 ELSE 2 END,
    ISNULL(vt.Upvotes, 0) - ISNULL(vt.Downvotes, 0) DESC,
    q.CreationDate DESC
OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;