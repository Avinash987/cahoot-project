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
        var connectionString = _configuration.GetConnectionString("StackOverflowDb");

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            throw new InvalidOperationException("Missing connection string: StackOverflowDb");
        }

        const string sql = """
        DECLARE @SearchPrefix NVARCHAR(110) = @Query + '%';

        WITH CandidateQuestions AS (
            SELECT TOP (200)
                q.Id,
                q.Title,
                q.Body,
                q.OwnerUserId,
                q.CreationDate
            FROM dbo.Posts q
            WHERE q.PostTypeId = 1
            AND q.Title LIKE @SearchPrefix
            ORDER BY q.CreationDate DESC
        ),
        CandidateOwners AS (
            SELECT DISTINCT OwnerUserId AS UserId
            FROM CandidateQuestions
            WHERE OwnerUserId IS NOT NULL
        ),
        AnswerCounts AS (
            SELECT
                p.ParentId AS QuestionId,
                COUNT(*) AS TotalAnswers
            FROM dbo.Posts p
            WHERE p.PostTypeId = 2
            AND EXISTS (
                SELECT 1
                FROM CandidateQuestions cq
                WHERE cq.Id = p.ParentId
            )
            GROUP BY p.ParentId
        ),
        VoteTotals AS (
            SELECT
                v.PostId,
                SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
                SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes
            FROM dbo.Votes v
            WHERE v.VoteTypeId IN (2, 3)
            AND EXISTS (
                SELECT 1
                FROM CandidateQuestions cq
                WHERE cq.Id = v.PostId
            )
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
        FROM CandidateQuestions cq
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
        """;

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);

        var command = new CommandDefinition(
            sql,
            new
            {
                Query = query,
                Offset = offset,
                PageSize = pageSize
            },
            commandType: CommandType.Text,
            commandTimeout: 90,
            cancellationToken: cancellationToken);

        var results = await connection.QueryAsync<SearchResultDto>(command);
        return results.ToList();
    }
}
