USE StackOverflow2013;
GO

/* =========================================================
   Task 3 - Weekly Aggregate Reporting
   Includes:
   1) Supporting permanent indexes
   2) Optimized temp-table based weekly aggregation query

   Assumptions:
   - PostTypeId = 1 => Question
   - PostTypeId = 2 => Answer
   - Accepted answers are counted by the accepted answer post's CreationDate week
   - Active users = distinct users who either posted or voted in that week
   ========================================================= */


/* =========================================================
   1) Supporting Permanent Indexes
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
FROM sys.indexes
WHERE name = 'IX_Posts_AcceptedAnswerId'
    AND object_id = OBJECT_ID('dbo.Posts')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Posts_AcceptedAnswerId
    ON dbo.Posts (AcceptedAnswerId)
    INCLUDE (Id, PostTypeId, CreationDate);
END
GO

IF NOT EXISTS (
    SELECT 1
FROM sys.indexes
WHERE name = 'IX_Posts_PostTypeId_CreationDate'
    AND object_id = OBJECT_ID('dbo.Posts')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Posts_PostTypeId_CreationDate
    ON dbo.Posts (PostTypeId, CreationDate)
    INCLUDE (Id, OwnerUserId, AcceptedAnswerId, ParentId);
END
GO

IF NOT EXISTS (
    SELECT 1
FROM sys.indexes
WHERE name = 'IX_Votes_CreationDate_UserId'
    AND object_id = OBJECT_ID('dbo.Votes')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Votes_CreationDate_UserId
    ON dbo.Votes (CreationDate, UserId)
    INCLUDE (PostId, VoteTypeId);
END
GO

IF NOT EXISTS (
    SELECT 1
FROM sys.indexes
WHERE name = 'IX_Users_CreationDate'
    AND object_id = OBJECT_ID('dbo.Users')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Users_CreationDate
    ON dbo.Users (CreationDate)
    INCLUDE (Id);
END
GO


/* =========================================================
   2) Optimized Weekly Aggregate Query
   ========================================================= */

IF OBJECT_ID('tempdb..#PostWeeks') IS NOT NULL DROP TABLE #PostWeeks;
IF OBJECT_ID('tempdb..#AcceptedAnswerWeeks') IS NOT NULL DROP TABLE #AcceptedAnswerWeeks;
IF OBJECT_ID('tempdb..#VoteWeeks') IS NOT NULL DROP TABLE #VoteWeeks;
IF OBJECT_ID('tempdb..#NewUserWeeks') IS NOT NULL DROP TABLE #NewUserWeeks;
IF OBJECT_ID('tempdb..#ActiveUsers') IS NOT NULL DROP TABLE #ActiveUsers;
IF OBJECT_ID('tempdb..#AllWeeks') IS NOT NULL DROP TABLE #AllWeeks;
GO

/* Weekly questions and answers */
SELECT
    DATEADD(WEEK, DATEDIFF(WEEK, 0, p.CreationDate), 0) AS WeekStart,
    SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount,
    SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
INTO #PostWeeks
FROM dbo.Posts p
WHERE p.PostTypeId IN (1, 2)
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, p.CreationDate), 0);

CREATE CLUSTERED INDEX IX_#PostWeeks_WeekStart
ON #PostWeeks (WeekStart);
GO

/* Weekly accepted answers */
SELECT
    DATEADD(WEEK, DATEDIFF(WEEK, 0, a.CreationDate), 0) AS WeekStart,
    COUNT(*) AS AcceptedAnswerCount
INTO #AcceptedAnswerWeeks
FROM dbo.Posts q
    JOIN dbo.Posts a
    ON a.Id = q.AcceptedAnswerId
WHERE q.PostTypeId = 1
    AND q.AcceptedAnswerId IS NOT NULL
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, a.CreationDate), 0);

CREATE CLUSTERED INDEX IX_#AcceptedAnswerWeeks_WeekStart
ON #AcceptedAnswerWeeks (WeekStart);
GO

/* Weekly votes */
SELECT
    DATEADD(WEEK, DATEDIFF(WEEK, 0, v.CreationDate), 0) AS WeekStart,
    COUNT(*) AS VoteCount
INTO #VoteWeeks
FROM dbo.Votes v
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, v.CreationDate), 0);

CREATE CLUSTERED INDEX IX_#VoteWeeks_WeekStart
ON #VoteWeeks (WeekStart);
GO

/* Weekly new users */
SELECT
    DATEADD(WEEK, DATEDIFF(WEEK, 0, u.CreationDate), 0) AS WeekStart,
    COUNT(*) AS NewUserCount
INTO #NewUserWeeks
FROM dbo.Users u
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, u.CreationDate), 0);

CREATE CLUSTERED INDEX IX_#NewUserWeeks_WeekStart
ON #NewUserWeeks (WeekStart);
GO

/* Weekly active users */
SELECT
    x.WeekStart,
    COUNT(DISTINCT x.UserId) AS ActiveUserCount
INTO #ActiveUsers
FROM (
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
) x
GROUP BY x.WeekStart;

CREATE CLUSTERED INDEX IX_#ActiveUsers_WeekStart
ON #ActiveUsers (WeekStart);
GO

/* Unified week timeline */
    SELECT WeekStart
    INTO #AllWeeks
    FROM #PostWeeks
UNION
    SELECT WeekStart
    FROM #AcceptedAnswerWeeks
UNION
    SELECT WeekStart
    FROM #VoteWeeks
UNION
    SELECT WeekStart
    FROM #NewUserWeeks
UNION
    SELECT WeekStart
    FROM #ActiveUsers;

CREATE CLUSTERED INDEX IX_#AllWeeks_WeekStart
ON #AllWeeks (WeekStart);
GO

/* Final result */
SELECT
    aw.WeekStart AS FirstDateOfWeek,
    ISNULL(pw.QuestionCount, 0) AS QuestionCount,
    ISNULL(pw.AnswerCount, 0) AS AnswerCount,
    ISNULL(aaw.AcceptedAnswerCount, 0) AS AcceptedAnswerCount,
    ISNULL(vw.VoteCount, 0) AS VoteCount,
    ISNULL(nuw.NewUserCount, 0) AS NewUserCount,
    ISNULL(au.ActiveUserCount, 0) AS ActiveUserCount
FROM #AllWeeks aw
    LEFT JOIN #PostWeeks pw
    ON pw.WeekStart = aw.WeekStart
    LEFT JOIN #AcceptedAnswerWeeks aaw
    ON aaw.WeekStart = aw.WeekStart
    LEFT JOIN #VoteWeeks vw
    ON vw.WeekStart = aw.WeekStart
    LEFT JOIN #NewUserWeeks nuw
    ON nuw.WeekStart = aw.WeekStart
    LEFT JOIN #ActiveUsers au
    ON au.WeekStart = aw.WeekStart
ORDER BY aw.WeekStart DESC;
GO