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

        if (!string.IsNullOrWhiteSpace(q) && q.Trim().Length >= 2)
        {
            model.Results = await _searchService.SearchAsync(q, model.Page, model.PageSize, cancellationToken);
            model.HasMore = model.Results.Count == model.PageSize;
        }

        return View(model);
    }

    [HttpGet]
    public async Task<IActionResult> More(string q, int page = 2, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(q) || q.Trim().Length < 2)
        {
            return Content(string.Empty);
        }

        var results = await _searchService.SearchAsync(q, Math.Max(1, page), PageSize, cancellationToken);
        return PartialView("_SearchResults", results);
    }
}