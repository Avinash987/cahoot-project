using Dapper;
using Microsoft.Data.SqlClient;
using StackOverflowSearchWeb.Models.Search;
using System.Data;

namespace StackOverflowSearchWeb.Services.Search;

public class SearchService : ISearchService
{
    private readonly IConfiguration _configuration;

    public SearchService(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    public async Task<List<SearchResultDto>> SearchAsync(
        string query,
        int page,
        int pageSize,
        CancellationToken cancellationToken = default)
    {
        query = query?.Trim() ?? string.Empty;

        if (query.Length < 2)
        {
            return new List<SearchResultDto>();
        }

        page = Math.Max(1, page);
        pageSize = Math.Max(1, pageSize);

        var offset = (page - 1) * pageSize;
        var seedTerm = query.Split(' ', StringSplitOptions.RemoveEmptyEntries)[0];
        var connectionString = _configuration.GetConnectionString("StackOverflowDb");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException("Missing connection string: StackOverflowDb");
        }

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var candidates = new List<CandidateSearchRow>();
        var searchParams = new DynamicParameters();
        searchParams.Add("SearchPrefix", query + "%", DbType.String, size: 110);
        searchParams.Add("TagPrefix", "<" + seedTerm + ">%", DbType.String, size: 110);

        candidates.AddRange(await connection.QueryAsync<CandidateSearchRow>(
            new CommandDefinition(
                """
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
                """,
                searchParams,
                commandTimeout: 90,
                cancellationToken: cancellationToken)));

        candidates.AddRange(await connection.QueryAsync<CandidateSearchRow>(
            new CommandDefinition(
                """
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
                """,
                searchParams,
                commandTimeout: 90,
                cancellationToken: cancellationToken)));

        var matchingQuestionIds = candidates
            .Where(candidate => candidate.ResultType == "Question")
            .Select(candidate => candidate.QuestionId)
            .Distinct()
            .Take(300)
            .ToArray();

        if (matchingQuestionIds.Length > 0)
        {
            candidates.AddRange(await connection.QueryAsync<CandidateSearchRow>(
                new CommandDefinition(
                    """
                    SELECT TOP (100)
                        q.Id AS QuestionId,
                        a.Id AS SourcePostId,
                        q.Title,
                        a.Body,
                        q.OwnerUserId,
                        a.CreationDate,
                        3 AS RelevanceRank,
                        N'Answer' AS ResultType,
                        N'Answer under matching question' AS MatchReason
                    FROM dbo.Posts a WITH (INDEX(IX_Posts_ParentId_PostTypeId))
                    INNER JOIN dbo.Posts q
                        ON q.Id = a.ParentId
                    WHERE a.PostTypeId = 2
                    AND a.ParentId IN @QuestionIds
                    ORDER BY a.CreationDate DESC;
                    """,
                    new { QuestionIds = matchingQuestionIds },
                    commandTimeout: 90,
                    cancellationToken: cancellationToken)));
        }

        var pageCandidates = candidates
            .GroupBy(candidate => candidate.SourcePostId)
            .Select(group => group
                .OrderBy(candidate => candidate.RelevanceRank)
                .ThenByDescending(candidate => candidate.CreationDate)
                .First())
            .OrderBy(candidate => candidate.RelevanceRank)
            .ThenByDescending(candidate => candidate.CreationDate)
            .Skip(offset)
            .Take(pageSize)
            .ToList();

        if (pageCandidates.Count == 0)
        {
            return new List<SearchResultDto>();
        }

        var questionIds = pageCandidates
            .Select(candidate => candidate.QuestionId)
            .Distinct()
            .ToArray();

        var sourcePostIds = pageCandidates
            .Select(candidate => candidate.SourcePostId)
            .Distinct()
            .ToArray();

        var ownerUserIds = pageCandidates
            .Where(candidate => candidate.OwnerUserId.HasValue)
            .Select(candidate => candidate.OwnerUserId!.Value)
            .Distinct()
            .ToArray();

        var answerCounts = await LoadAnswerCountsAsync(connection, questionIds, cancellationToken);
        var voteTotals = await LoadVoteTotalsAsync(connection, sourcePostIds, cancellationToken);
        var users = await LoadUsersAsync(connection, ownerUserIds, cancellationToken);
        var badgeCounts = await LoadBadgeCountsAsync(connection, ownerUserIds, cancellationToken);

        return pageCandidates
            .Select(candidate =>
            {
                users.TryGetValue(candidate.OwnerUserId ?? 0, out var user);

                return new SearchResultDto
                {
                    QuestionId = candidate.QuestionId,
                    SourcePostId = candidate.SourcePostId,
                    Title = candidate.Title ?? string.Empty,
                    ResultType = candidate.ResultType,
                    MatchReason = candidate.MatchReason,
                    Snippet = candidate.Body ?? string.Empty,
                    TotalVotes = voteTotals.GetValueOrDefault(candidate.SourcePostId),
                    TotalAnswers = answerCounts.GetValueOrDefault(candidate.QuestionId),
                    AskedBy = user?.DisplayName ?? "Unknown User",
                    Reputation = user?.Reputation,
                    TotalBadges = badgeCounts.GetValueOrDefault(candidate.OwnerUserId ?? 0)
                };
            })
            .ToList();
    }

    private static async Task<Dictionary<int, int>> LoadAnswerCountsAsync(
        SqlConnection connection,
        int[] questionIds,
        CancellationToken cancellationToken)
    {
        if (questionIds.Length == 0)
        {
            return new Dictionary<int, int>();
        }

        var rows = await connection.QueryAsync<AnswerCountRow>(
            new CommandDefinition(
                """
                SELECT
                    p.ParentId AS QuestionId,
                    COUNT(*) AS TotalAnswers
                FROM dbo.Posts p WITH (INDEX(IX_Posts_ParentId_PostTypeId))
                WHERE p.PostTypeId = 2
                AND p.ParentId IN @QuestionIds
                GROUP BY p.ParentId;
                """,
                new { QuestionIds = questionIds },
                commandTimeout: 90,
                cancellationToken: cancellationToken));

        return rows.ToDictionary(row => row.QuestionId, row => row.TotalAnswers);
    }

    private static async Task<Dictionary<int, int>> LoadVoteTotalsAsync(
        SqlConnection connection,
        int[] sourcePostIds,
        CancellationToken cancellationToken)
    {
        if (sourcePostIds.Length == 0)
        {
            return new Dictionary<int, int>();
        }

        var rows = await connection.QueryAsync<VoteTotalRow>(
            new CommandDefinition(
                """
                SELECT
                    v.PostId,
                    SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)
                        - SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS TotalVotes
                FROM dbo.Votes v WITH (INDEX(IX_Votes_PostId_VoteTypeId))
                WHERE v.VoteTypeId IN (2, 3)
                AND v.PostId IN @SourcePostIds
                GROUP BY v.PostId;
                """,
                new { SourcePostIds = sourcePostIds },
                commandTimeout: 90,
                cancellationToken: cancellationToken));

        return rows.ToDictionary(row => row.PostId, row => row.TotalVotes);
    }

    private static async Task<Dictionary<int, UserRow>> LoadUsersAsync(
        SqlConnection connection,
        int[] ownerUserIds,
        CancellationToken cancellationToken)
    {
        if (ownerUserIds.Length == 0)
        {
            return new Dictionary<int, UserRow>();
        }

        var rows = await connection.QueryAsync<UserRow>(
            new CommandDefinition(
                """
                SELECT
                    u.Id AS UserId,
                    u.DisplayName,
                    u.Reputation
                FROM dbo.Users u
                WHERE u.Id IN @OwnerUserIds;
                """,
                new { OwnerUserIds = ownerUserIds },
                commandTimeout: 90,
                cancellationToken: cancellationToken));

        return rows.ToDictionary(row => row.UserId);
    }

    private static async Task<Dictionary<int, int>> LoadBadgeCountsAsync(
        SqlConnection connection,
        int[] ownerUserIds,
        CancellationToken cancellationToken)
    {
        if (ownerUserIds.Length == 0)
        {
            return new Dictionary<int, int>();
        }

        var rows = await connection.QueryAsync<BadgeCountRow>(
            new CommandDefinition(
                """
                SELECT
                    b.UserId,
                    COUNT(*) AS TotalBadges
                FROM dbo.Badges b WITH (INDEX(IX_Badges_UserId))
                WHERE b.UserId IN @OwnerUserIds
                GROUP BY b.UserId;
                """,
                new { OwnerUserIds = ownerUserIds },
                commandTimeout: 90,
                cancellationToken: cancellationToken));

        return rows.ToDictionary(row => row.UserId, row => row.TotalBadges);
    }

    private sealed class CandidateSearchRow
    {
        public int QuestionId { get; set; }
        public int SourcePostId { get; set; }
        public string? Title { get; set; }
        public string? Body { get; set; }
        public int? OwnerUserId { get; set; }
        public DateTime CreationDate { get; set; }
        public int RelevanceRank { get; set; }
        public string ResultType { get; set; } = "Question";
        public string MatchReason { get; set; } = string.Empty;
    }

    private sealed class AnswerCountRow
    {
        public int QuestionId { get; set; }
        public int TotalAnswers { get; set; }
    }

    private sealed class VoteTotalRow
    {
        public int PostId { get; set; }
        public int TotalVotes { get; set; }
    }

    private sealed class UserRow
    {
        public int UserId { get; set; }
        public string DisplayName { get; set; } = string.Empty;
        public int? Reputation { get; set; }
    }

    private sealed class BadgeCountRow
    {
        public int UserId { get; set; }
        public int TotalBadges { get; set; }
    }
}
