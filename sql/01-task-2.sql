WITH
    VoteAgg
    AS
    (
        SELECT
            v.PostId,
            SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS TotalUpvotes,
            SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalDownvotes
        FROM dbo.Votes AS v
        WHERE v.VoteTypeId IN (2, 3)
        GROUP BY v.PostId
    ),
    PostVoteSummary
    AS
    (
        SELECT
            CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
        END AS PostType,
            DATENAME(WEEKDAY, p.CreationDate) AS DayOfWeek,
            DATEPART(WEEKDAY, p.CreationDate) AS DayOfWeekNumber,
            ISNULL(va.TotalUpvotes, 0) AS TotalUpvotes,
            ISNULL(va.TotalDownvotes, 0) AS TotalDownvotes
        FROM dbo.Posts AS p
            LEFT JOIN VoteAgg AS va
            ON va.PostId = p.Id
        WHERE p.PostTypeId IN (1, 2)
    )
SELECT
    PostType,
    DayOfWeek,
    COUNT_BIG(*) AS TotalPosts,
    SUM(TotalUpvotes) AS TotalUpvotes,
    SUM(TotalDownvotes) AS TotalDownvotes,
    CAST(
        1.0 * SUM(TotalUpvotes) / NULLIF(SUM(TotalDownvotes), 0)
        AS DECIMAL(19, 4)
    ) AS UpvoteDownvoteRatio
FROM PostVoteSummary
GROUP BY
    PostType,
    DayOfWeek,
    DayOfWeekNumber
ORDER BY
    UpvoteDownvoteRatio DESC,
    TotalPosts DESC;