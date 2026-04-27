namespace StackOverflowSearchWeb.Models.Search;

public class SearchPageViewModel
{
    public string Query { get; set; } = string.Empty;
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public bool HasMore { get; set; }
    public List<SearchResultDto> Results { get; set; } = new();
}