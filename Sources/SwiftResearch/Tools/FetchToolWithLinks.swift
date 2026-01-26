import Foundation
import SwiftAgent
import RemarkKit

/// A tool for fetching content from URLs with link extraction.
///
/// Extends the standard URL fetch functionality to also extract
/// and return links found within the page content.
public struct FetchToolWithLinks: Tool, Sendable {
    public typealias Arguments = FetchWithLinksInput
    public typealias Output = FetchWithLinksOutput

    public static let name = "WebFetch"
    public var name: String { Self.name }

    public static let description = """
    Fetch content from multiple URLs in parallel and extract links found in each page.
    Accepts a list of URLs and returns content as Markdown along with links for each.
    Use this to efficiently read multiple web pages at once.
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        FetchWithLinksInput.generationSchema
    }

    public init() {}

    public func call(arguments: FetchWithLinksInput) async throws -> FetchWithLinksOutput {
        // Fetch all URLs in parallel
        let results = await withTaskGroup(of: SingleFetchResult.self) { group in
            for urlString in arguments.urls {
                group.addTask {
                    await self.fetchSingleURL(urlString)
                }
            }

            var fetchResults: [SingleFetchResult] = []
            for await result in group {
                fetchResults.append(result)
            }
            return fetchResults
        }

        return FetchWithLinksOutput(results: results)
    }

    /// Fetches a single URL and returns the result.
    private func fetchSingleURL(_ urlString: String) async -> SingleFetchResult {
        guard let url = URL(string: urlString) else {
            return SingleFetchResult(
                success: false,
                content: "",
                links: [],
                url: urlString,
                message: "Invalid URL format"
            )
        }

        do {
            let remark = try await Remark.fetch(from: url)
            let markdown = remark.markdown
            let links = extractLinks(from: markdown, baseURL: urlString)

            return SingleFetchResult(
                success: true,
                content: markdown,
                links: links,
                url: urlString,
                message: "Successfully fetched page with \(links.count) links"
            )
        } catch {
            return SingleFetchResult(
                success: false,
                content: "",
                links: [],
                url: urlString,
                message: "Failed to fetch: \(error.localizedDescription)"
            )
        }
    }

    /// Extracts links from Markdown content.
    private func extractLinks(from markdown: String, baseURL: String) -> [PageLink] {
        var links: [PageLink] = []
        let pattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return links
        }

        let range = NSRange(markdown.startIndex..., in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: range)

        let baseURLObject = URL(string: baseURL)

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let textRange = Range(match.range(at: 1), in: markdown),
                  let urlRange = Range(match.range(at: 2), in: markdown) else {
                continue
            }

            let text = String(markdown[textRange])
            var urlString = String(markdown[urlRange])

            // Skip non-http links, anchors, and javascript
            guard !urlString.hasPrefix("#"),
                  !urlString.hasPrefix("javascript:"),
                  !urlString.hasPrefix("mailto:") else {
                continue
            }

            // Convert relative URLs to absolute
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                if let base = baseURLObject {
                    if let absoluteURL = URL(string: urlString, relativeTo: base) {
                        urlString = absoluteURL.absoluteString
                    }
                }
            }

            // Avoid duplicates
            if !links.contains(where: { $0.url == urlString }) {
                links.append(PageLink(url: urlString, text: text))
            }
        }

        return links
    }
}

// MARK: - Input/Output Types

/// Input for fetch with links operation.
@Generable
public struct FetchWithLinksInput: Sendable {
    @Guide(description: "List of URLs to fetch content from (parallel fetch)")
    public let urls: [String]
}

/// A link found within a page.
public struct PageLink: Sendable, Equatable {
    /// The URL of the link.
    public let url: String

    /// The anchor text of the link.
    public let text: String

    public init(url: String, text: String) {
        self.url = url
        self.text = text
    }
}

/// Result for a single URL fetch.
public struct SingleFetchResult: Sendable {
    /// Whether the fetch was successful.
    public let success: Bool

    /// The page content as Markdown.
    public let content: String

    /// Links found in the page.
    public let links: [PageLink]

    /// The original URL.
    public let url: String

    /// A message about the operation.
    public let message: String

    public init(success: Bool, content: String, links: [PageLink], url: String, message: String) {
        self.success = success
        self.content = content
        self.links = links
        self.url = url
        self.message = message
    }
}

/// Output for fetch with links operation (supports multiple URLs).
public struct FetchWithLinksOutput: Sendable {
    /// Results for each URL fetched.
    public let results: [SingleFetchResult]

    /// Number of successful fetches.
    public var successCount: Int {
        results.filter { $0.success }.count
    }

    /// Number of failed fetches.
    public var failedCount: Int {
        results.filter { !$0.success }.count
    }

    public init(results: [SingleFetchResult]) {
        self.results = results
    }
}

extension FetchWithLinksOutput: CustomStringConvertible {
    public var description: String {
        var output = "WebFetch [Fetched \(successCount)/\(results.count) URLs]\n"

        for result in results {
            let status = result.success ? "✓" : "✗"
            output += "\n--- \(status) \(result.url) ---\n"
            output += "\(result.message)\n"

            if result.success {
                // Truncate content if too long
                let maxContentLength = 1500
                let truncatedContent = result.content.count > maxContentLength
                    ? String(result.content.prefix(maxContentLength)) + "\n...[truncated]"
                    : result.content

                output += "\n## Content\n\(truncatedContent)\n"

                if !result.links.isEmpty {
                    output += "\n## Links (\(result.links.count) found)\n"
                    for (index, link) in result.links.prefix(10).enumerated() {
                        output += "\(index + 1). [\(link.text)](\(link.url))\n"
                    }
                    if result.links.count > 10 {
                        output += "... and \(result.links.count - 10) more links\n"
                    }
                }
            }
        }

        return output
    }
}

extension FetchWithLinksOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}
