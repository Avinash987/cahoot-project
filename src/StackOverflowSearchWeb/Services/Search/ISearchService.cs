using StackOverflowSearchWeb.Models.Search;

namespace StackOverflowSearchWeb.Services.Search;

public interface ISearchService
{
    Task<List<SearchResultDto>> SearchAsync(string query, int page, int pageSize, CancellationToken cancellationToken = default);
}