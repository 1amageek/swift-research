import Foundation
import SwiftAgent

/// Configuration for the crawler.
///
/// Contains crawler-specific settings like search engine and domain filtering.
/// LLM configuration is handled externally via LanguageModelSession.
@Contextable
public struct CrawlerConfiguration: Sendable {
    /// The search engine to use for keyword searches.
    public let searchEngine: SearchEngine

    /// Delay between HTTP requests.
    public let requestDelay: Duration

    /// Domains to allow. If `nil`, all domains are allowed.
    public let allowedDomains: [String]?

    /// Domains to block.
    public let blockedDomains: [String]

    /// The underlying research configuration.
    public let researchConfiguration: ResearchConfiguration

    /// Domain context for query disambiguation.
    ///
    /// When set, this context helps the LLM correctly interpret ambiguous queries.
    /// For example, with domain context "Software development, AI, hardware",
    /// the query "What is Swift?" will be interpreted as Swift programming language
    /// rather than SWIFT financial network.
    public let domainContext: String?

    /// Creates a new crawler configuration.
    ///
    /// - Parameters:
    ///   - searchEngine: The search engine to use. Defaults to DuckDuckGo.
    ///   - requestDelay: Delay between requests. Defaults to 500ms.
    ///   - allowedDomains: Domains to allow. Defaults to `nil` (all allowed).
    ///   - blockedDomains: Domains to block. Defaults to empty.
    ///   - researchConfiguration: The research configuration to use.
    ///   - domainContext: Domain context for query disambiguation. Defaults to `nil`.
    public init(
        searchEngine: SearchEngine = .duckDuckGo,
        requestDelay: Duration = .milliseconds(500),
        allowedDomains: [String]? = nil,
        blockedDomains: [String] = [],
        researchConfiguration: ResearchConfiguration = .shared,
        domainContext: String? = nil
    ) {
        self.searchEngine = searchEngine
        self.requestDelay = requestDelay
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.researchConfiguration = researchConfiguration
        self.domainContext = domainContext
    }

    /// The default configuration.
    public static let `default` = CrawlerConfiguration()

    /// The default value for Contextable conformance.
    public static var defaultValue: CrawlerConfiguration { .default }
}

/// Supported search engines for keyword searches.
public enum SearchEngine: Sendable {
    /// DuckDuckGo search engine.
    case duckDuckGo
    /// Google search engine.
    case google
    /// Bing search engine.
    case bing

    /// The URL template for search queries.
    ///
    /// Use `%@` as a placeholder for the URL-encoded query string.
    public var searchURLTemplate: String {
        switch self {
        case .duckDuckGo:
            return "https://duckduckgo.com/html/?q=%@"
        case .google:
            return "https://www.google.com/search?q=%@"
        case .bing:
            return "https://www.bing.com/search?q=%@"
        }
    }

    /// Creates a search URL for the given query.
    ///
    /// - Parameter query: The search query string.
    /// - Returns: The search URL, or `nil` if the query cannot be encoded.
    public func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let urlString = String(format: searchURLTemplate, encoded)
        return URL(string: urlString)
    }
}
