import Foundation
import SwiftAgent
import RemarkKit

/// A tool for performing web searches using DuckDuckGo.
///
/// Uses RemarkKit to fetch and parse DuckDuckGo search results,
/// returning a list of URLs with titles.
public struct WebSearchTool: Tool, Sendable {
    public typealias Arguments = WebSearchInput
    public typealias Output = WebSearchOutput

    public static let name = "WebSearch"
    public var name: String { Self.name }

    public static let description = """
    Search the web to find relevant URLs for a given query.
    Returns a list of search results with titles and URLs.
    Use this to discover information before fetching specific pages.
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        WebSearchInput.generationSchema
    }

    private let blockedDomains: [String]

    public init(blockedDomains: [String] = []) {
        self.blockedDomains = blockedDomains
    }

    /// Parses search results from DuckDuckGo markdown output.
    /// Each result consists of a link followed by a snippet paragraph.
    private func parseSearchResults(from markdown: String, blockedDomains: [String]) -> [SearchResult] {
        var results: [SearchResult] = []
        var seenURLs: Set<String> = []

        // Pattern: [Title](URL) followed by text until next link or end
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
            return results
        }

        let range = NSRange(markdown.startIndex..., in: markdown)
        let matches = regex.matches(in: markdown, options: [], range: range)

        for (i, match) in matches.enumerated() {
            guard match.numberOfRanges >= 3,
                  let titleRange = Range(match.range(at: 1), in: markdown),
                  let urlRange = Range(match.range(at: 2), in: markdown) else {
                continue
            }

            let title = String(markdown[titleRange])
            let urlString = String(markdown[urlRange])

            // Validate URL
            guard let url = URL(string: urlString),
                  let host = url.host,
                  url.scheme == "https" else {
                continue
            }

            // Skip blocked domains
            if blockedDomains.contains(where: { host.contains($0) }) {
                continue
            }

            // Skip search engine internal links
            let internalPatterns = [
                "duckduckgo.", ".google.", "google.com",
                ".bing.", "bing.com", "yahoo.com", ".yahoo.",
                "yandex.", "baidu.com"
            ]
            if internalPatterns.contains(where: { host.contains($0) }) {
                continue
            }

            // Skip duplicates
            if seenURLs.contains(urlString) {
                continue
            }
            seenURLs.insert(urlString)

            // Extract snippet: text between this link and the next link
            let matchEnd = match.range.upperBound
            let nextMatchStart = (i + 1 < matches.count) ? matches[i + 1].range.lowerBound : markdown.utf16.count

            if matchEnd < nextMatchStart,
               let snippetStartIndex = markdown.utf16.index(markdown.utf16.startIndex, offsetBy: matchEnd, limitedBy: markdown.utf16.endIndex),
               let snippetEndIndex = markdown.utf16.index(markdown.utf16.startIndex, offsetBy: nextMatchStart, limitedBy: markdown.utf16.endIndex) {
                let startIndex = String.Index(snippetStartIndex, within: markdown) ?? markdown.startIndex
                let endIndex = String.Index(snippetEndIndex, within: markdown) ?? markdown.endIndex
                var snippet = String(markdown[startIndex..<endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "  ", with: " ")

                // Truncate snippet if too long
                if snippet.count > 200 {
                    snippet = String(snippet.prefix(200)) + "..."
                }

                results.append(SearchResult(
                    title: title,
                    url: urlString,
                    snippet: snippet
                ))
            } else {
                results.append(SearchResult(
                    title: title,
                    url: urlString,
                    snippet: ""
                ))
            }
        }

        return results
    }

    public func call(arguments: WebSearchInput) async throws -> WebSearchOutput {
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return WebSearchOutput(
                success: false,
                results: [],
                query: query,
                message: "Search query cannot be empty"
            )
        }

        // Build DuckDuckGo search URL
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://html.duckduckgo.com/html/?q=\(encodedQuery)") else {
            return WebSearchOutput(
                success: false,
                results: [],
                query: query,
                message: "Failed to encode search query"
            )
        }

        do {
            let remark = try await Remark.fetch(from: searchURL, timeout: 15)
            let markdown = remark.markdown

            // Parse search results from markdown
            let results = parseSearchResults(from: markdown, blockedDomains: blockedDomains)

            if results.isEmpty {
                return WebSearchOutput(
                    success: true,
                    results: [],
                    query: query,
                    message: "No results found for query"
                )
            }

            return WebSearchOutput(
                success: true,
                results: Array(results.prefix(arguments.limit > 0 ? arguments.limit : 10)),
                query: query,
                message: "Found \(results.count) results"
            )
        } catch {
            return WebSearchOutput(
                success: false,
                results: [],
                query: query,
                message: "Search failed: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Input/Output Types

/// Input for web search operations.
@Generable
public struct WebSearchInput: Sendable {
    @Guide(description: "The search query keywords")
    public let query: String

    @Guide(description: "Maximum number of results to return (default: 10)")
    public let limit: Int
}

/// A single search result.
public struct SearchResult: Sendable {
    /// The title of the search result.
    public let title: String

    /// The URL of the search result.
    public let url: String

    /// A brief description/snippet from the search result.
    public let snippet: String

    public init(title: String, url: String, snippet: String = "") {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

/// Output for web search operations.
public struct WebSearchOutput: Sendable {
    /// Whether the search was successful.
    public let success: Bool

    /// The search results.
    public let results: [SearchResult]

    /// The original query.
    public let query: String

    /// A message about the operation.
    public let message: String

    public init(success: Bool, results: [SearchResult], query: String, message: String) {
        self.success = success
        self.results = results
        self.query = query
        self.message = message
    }
}

extension WebSearchOutput: CustomStringConvertible {
    public var description: String {
        let status = success ? "Success" : "Failed"
        var output = """
        WebSearch [\(status)]
        Query: \(query)
        \(message)
        """

        if !results.isEmpty {
            output += "\n\nResults:"
            for (index, result) in results.enumerated() {
                output += "\n\n\(index + 1). \(result.title)"
                output += "\n   URL: \(result.url)"
                if !result.snippet.isEmpty {
                    output += "\n   \(result.snippet)"
                }
            }
        }

        return output
    }
}

extension WebSearchOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}
