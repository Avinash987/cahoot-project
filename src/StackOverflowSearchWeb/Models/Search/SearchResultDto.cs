namespace StackOverflowSearchWeb.Models.Search;

public class SearchResultDto
{
    public int QuestionId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Snippet { get; set; } = string.Empty;
    public int TotalVotes { get; set; }
    public int TotalAnswers { get; set; }
    public string AskedBy { get; set; } = string.Empty;
    public int? Reputation { get; set; }
    public int TotalBadges { get; set; }
}