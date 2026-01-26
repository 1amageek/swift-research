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
            let links = try remark.extractLinks()

            var seenURLs: Set<String> = []
            var results: [SearchResult] = []

            for link in links {
                guard let url = URL(string: link.url),
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
                let urlString = url.absoluteString
                if seenURLs.contains(urlString) {
                    continue
                }
                seenURLs.insert(urlString)

                results.append(SearchResult(
                    title: link.text.isEmpty ? host : link.text,
                    url: urlString
                ))
            }

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

    public init(title: String, url: String) {
        self.title = title
        self.url = url
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
                output += "\n\(index + 1). \(result.title)"
                output += "\n   URL: \(result.url)"
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
