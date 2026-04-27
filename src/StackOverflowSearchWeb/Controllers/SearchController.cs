using Microsoft.AspNetCore.Mvc;
using StackOverflowSearchWeb.Models.Search;
using StackOverflowSearchWeb.Services.Search;

namespace StackOverflowSearchWeb.Controllers;

public class SearchController : Controller
{
    private readonly ISearchService _searchService;
    private const int PageSize = 10;

    public SearchController(ISearchService searchService)
    {
        _searchService = searchService;
    }

    [HttpGet]
    public async Task<IActionResult> Index(string q = "", int page = 1, CancellationToken cancellationToken = default)
    {
        var model = new SearchPageViewModel
        {
            Query = q ?? string.Empty,
            Page = Math.Max(1, page),
            PageSize = PageSize
        };

        if (!string.IsNullOrWhiteSpace(q))
        {
            model.Results = await _searchService.SearchAsync(q, model.Page, model.PageSize, cancellationToken);
            model.HasMore = model.Results.Count == model.PageSize;
        }

        return View(model);
    }
}