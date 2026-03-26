#!/usr/bin/env node
// Fetches a URL and extracts the main article content using Mozilla's Readability.
// Usage: node scraper.js <url>
// Outputs clean text content to stdout.

const { Readability } = require("@mozilla/readability");
const { parseHTML } = require("linkedom");

const url = process.argv[2];
if (!url) {
  console.error("Usage: node scraper.js <url>");
  process.exit(1);
}

async function main() {
  try {
    const response = await fetch(url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
      },
      signal: AbortSignal.timeout(15000),
    });

    if (!response.ok) {
      console.error(`HTTP ${response.status}`);
      process.exit(1);
    }

    const html = await response.text();
    const { document } = parseHTML(html);

    const reader = new Readability(document);
    const article = reader.parse();

    if (article && article.textContent) {
      // Clean up whitespace
      const text = article.textContent
        .replace(/\n{3,}/g, "\n\n")
        .replace(/[ \t]+/g, " ")
        .trim();

      // Truncate to reasonable size
      const maxLen = 8000;
      if (text.length > maxLen) {
        console.log(text.substring(0, maxLen) + "\n\n[Truncated]");
      } else {
        console.log(text);
      }
    } else {
      // Fallback: just strip HTML tags
      const text = html
        .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
        .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
        .replace(/<[^>]+>/g, " ")
        .replace(/\s+/g, " ")
        .trim()
        .substring(0, 8000);
      console.log(text);
    }
  } catch (e) {
    console.error("Error:", e.message);
    process.exit(1);
  }
}

main();
