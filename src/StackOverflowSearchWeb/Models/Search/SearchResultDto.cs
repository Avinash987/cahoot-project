using System.Net;
using System.Text.RegularExpressions;

namespace StackOverflowSearchWeb.Models.Search;

public class SearchResultDto
{
    public int QuestionId { get; set; }
    public string Title { get; set; } = string.Empty;

    // raw DB value
    public string Snippet { get; set; } = string.Empty;

    public int TotalVotes { get; set; }
    public int TotalAnswers { get; set; }
    public string AskedBy { get; set; } = string.Empty;
    public int? Reputation { get; set; }
    public int TotalBadges { get; set; }

    public string CleanSnippet
    {
        get
        {
            if (string.IsNullOrWhiteSpace(Snippet))
                return string.Empty;

            var noHtml = Regex.Replace(Snippet, "<.*?>", " ");
            var decoded = WebUtility.HtmlDecode(noHtml);
            var normalized = Regex.Replace(decoded, @"\s+", " ").Trim();

            return normalized.Length <= 140
                ? normalized
                : normalized[..140].TrimEnd() + "...";
        }
    }
}