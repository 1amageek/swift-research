import Foundation
import SwiftAgent
import RemarkKit

/// Input for keyword search.
public struct KeywordSearchInput: Sendable {
    /// The keyword to search for.
    public let keyword: String

    /// Creates a new keyword search input.
    ///
    /// - Parameter keyword: The keyword to search for.
    public init(keyword: String) {
        self.keyword = keyword
    }
}

/// A step that performs keyword search and returns a list of URLs.
///
/// Uses the configured search engine to find relevant pages and filters
/// the results to exclude blocked domains and search engine internal links.
public struct SearchStep: Step, Sendable {
    public typealias Input = KeywordSearchInput
    public typealias Output = [URL]

    private let searchEngine: SearchEngine
    private let blockedDomains: Set<String>

    /// Creates a new search step.
    ///
    /// - Parameters:
    ///   - searchEngine: The search engine to use.
    ///   - blockedDomains: Domains to exclude from results.
    public init(
        searchEngine: SearchEngine = .duckDuckGo,
        blockedDomains: [String] = []
    ) {
        self.searchEngine = searchEngine
        self.blockedDomains = Set(blockedDomains)
    }

    public func run(_ input: KeywordSearchInput) async throws -> [URL] {
        guard let searchURL = searchEngine.searchURL(for: input.keyword) else {
            throw CrawlerError.invalidURL(input.keyword)
        }

        printFlush("🔍 Searching: \(input.keyword)")

        let remark = try await Remark.fetch(from: searchURL)
        let links = try remark.extractLinks()

        var seenURLs: Set<URL> = []
        let urls = links
            .compactMap { URL(string: $0.url) }
            .filter { url in
                guard let host = url.host else { return false }

                // Exclude blocked domains
                if blockedDomains.contains(where: { host.contains($0) }) {
                    return false
                }

                // Exclude search engine internal links
                let internalDomainPatterns = [
                    "duckduckgo.",
                    ".google.",
                    "google.com",
                    ".bing.",
                    "bing.com",
                    "yahoo.com",
                    ".yahoo.",
                    "yandex.",
                    "baidu.com",
                ]
                if internalDomainPatterns.contains(where: { host.contains($0) }) {
                    return false
                }

                // Only allow HTTPS
                return url.scheme == "https"
            }
            .filter { url in
                // Remove duplicates while preserving order
                if seenURLs.contains(url) {
                    return false
                }
                seenURLs.insert(url)
                return true
            }

        printFlush("   Found \(urls.count) URLs")

        if urls.isEmpty {
            throw CrawlerError.noURLsFound
        }

        return Array(urls)
    }
}

// MARK: - Convenience Extensions

extension SearchStep {
    /// Creates a search step from a crawler configuration.
    ///
    /// - Parameter configuration: The crawler configuration.
    /// - Returns: A configured search step.
    public static func from(configuration: CrawlerConfiguration) -> SearchStep {
        SearchStep(
            searchEngine: configuration.searchEngine,
            blockedDomains: configuration.blockedDomains
        )
    }
}
