using System.Net;
using System.Text.RegularExpressions;
using SmartReader;

namespace HyprChat.Services;

/// <summary>
/// Web search via DuckDuckGo and page content extraction via SmartReader.
/// Replaces WebSearchService.qml + scraper.js — no Node.js dependency.
/// </summary>
public sealed partial class WebService(HttpClient http)
{
    private readonly HttpClient _http = http;
    private const int MaxPageLength = 8000;

    public async Task<string> SearchAsync(string query, CancellationToken ct = default)
    {
        try
        {
            var encoded = Uri.EscapeDataString(query).Replace("%20", "+");
            var url = $"https://html.duckduckgo.com/html/?q={encoded}";

            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.UserAgent.ParseAdd(
                "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");

            using var response = await this._http.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode)
                return $"Search failed: HTTP {(int)response.StatusCode}";

            var html = await response.Content.ReadAsStringAsync(ct);

            // Parse result links — match <a class="result__a" href="...">...</a>
            var results = new List<(string Title, string Url)>();
            var matches = ResultLinkRegex().Matches(html);

            foreach (Match m in matches)
            {
                var rawUrl = WebUtility.HtmlDecode(m.Groups[1].Value);
                var title = StripHtmlTags(WebUtility.HtmlDecode(m.Groups[2].Value));

                // Extract actual URL from DDG redirect
                var uddgMatch = UddgParamRegex().Match(rawUrl);
                var actualUrl = uddgMatch.Success
                    ? Uri.UnescapeDataString(uddgMatch.Groups[1].Value)
                    : rawUrl;

                if (!string.IsNullOrWhiteSpace(title) && !string.IsNullOrWhiteSpace(actualUrl))
                    results.Add((title.Trim(), actualUrl));
            }

            if (results.Count == 0)
                return "No results found.";

            var output = "Search results:\n\n";
            var count = Math.Min(results.Count, 8);
            for (var i = 0; i < count; i++)
            {
                var (Title, Url) = results[i];
                output += $"{i + 1}. **{Title}**\n   {Url}\n\n";
            }

            return output;
        }
        catch (TaskCanceledException)
        {
            return "Search timed out.";
        }
        catch (Exception ex)
        {
            return $"Search failed: {ex.Message}";
        }
    }

    public async Task<string> FetchPageAsync(string url, CancellationToken ct = default)
    {
        try
        {
            // Try SmartReader first (Readability.js equivalent)
            var article = await Reader.ParseArticleAsync(url);

            if (article.IsReadable && !string.IsNullOrWhiteSpace(article.TextContent))
            {
                var text = CleanText(article.TextContent);
                if (text.Length > MaxPageLength)
                    text = text[..MaxPageLength] + "\n\n[Truncated — page content too long]";
                return text;
            }

            // Fallback: fetch raw HTML and strip tags
            return await this.FetchFallbackAsync(url, ct);
        }
        catch (TaskCanceledException)
        {
            return $"Fetch timed out for: {url}";
        }
        catch
        {
            // SmartReader failed — try fallback
            try
            {
                return await this.FetchFallbackAsync(url, ct);
            }
            catch (Exception ex2)
            {
                return $"Failed to fetch page: {url}\nError: {ex2.Message}";
            }
        }
    }

    private async Task<string> FetchFallbackAsync(string url, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.UserAgent.ParseAdd(
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");

        using var response = await this._http.SendAsync(request, ct);
        var html = await response.Content.ReadAsStringAsync(ct);

        // Strip scripts, styles, and HTML tags
        var text = ScriptRegex().Replace(html, "");
        text = StyleRegex().Replace(text, "");
        text = HtmlTagRegex().Replace(text, " ");
        text = WebUtility.HtmlDecode(text);
        text = CleanText(text);

        if (text.Length > MaxPageLength)
            text = text[..MaxPageLength] + "\n\n[Truncated — page content too long]";

        return "[Extracted via fallback — formatting may be rough]\n\n" + text;
    }

    private static string CleanText(string text)
    {
        text = MultiNewlineRegex().Replace(text, "\n\n");
        text = MultiSpaceRegex().Replace(text, " ");
        return text.Trim();
    }

    private static string StripHtmlTags(string html) => HtmlTagRegex().Replace(html, "");

    [GeneratedRegex("""class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>""", RegexOptions.Singleline)]
    private static partial Regex ResultLinkRegex();

    [GeneratedRegex(@"uddg=([^&]+)")]
    private static partial Regex UddgParamRegex();

    [GeneratedRegex(@"<script[^>]*>[\s\S]*?</script>", RegexOptions.IgnoreCase)]
    private static partial Regex ScriptRegex();

    [GeneratedRegex(@"<style[^>]*>[\s\S]*?</style>", RegexOptions.IgnoreCase)]
    private static partial Regex StyleRegex();

    [GeneratedRegex(@"<[^>]+>")]
    private static partial Regex HtmlTagRegex();

    [GeneratedRegex(@"\n{3,}")]
    private static partial Regex MultiNewlineRegex();

    [GeneratedRegex(@"[ \t]+")]
    private static partial Regex MultiSpaceRegex();
}
