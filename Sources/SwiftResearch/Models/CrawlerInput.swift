import Foundation

/// Input for the crawler containing URLs and research objective.
public struct CrawlerInput: Sendable {
    /// The URLs to crawl.
    public let urls: [URL]

    /// The research objective.
    public let objective: String

    /// Creates a new crawler input.
    ///
    /// - Parameters:
    ///   - urls: The URLs to crawl.
    ///   - objective: The research objective.
    public init(
        urls: [URL],
        objective: String
    ) {
        self.urls = urls
        self.objective = objective
    }
}

/// Configuration for the crawler.
///
/// Contains crawler-specific settings like search engine and domain filtering.
/// LLM configuration is handled externally via LanguageModelSession.
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

    /// Creates a new crawler configuration.
    ///
    /// - Parameters:
    ///   - searchEngine: The search engine to use. Defaults to DuckDuckGo.
    ///   - requestDelay: Delay between requests. Defaults to 500ms.
    ///   - allowedDomains: Domains to allow. Defaults to `nil` (all allowed).
    ///   - blockedDomains: Domains to block. Defaults to empty.
    ///   - researchConfiguration: The research configuration to use.
    public init(
        searchEngine: SearchEngine = .duckDuckGo,
        requestDelay: Duration = .milliseconds(500),
        allowedDomains: [String]? = nil,
        blockedDomains: [String] = [],
        researchConfiguration: ResearchConfiguration = .shared
    ) {
        self.searchEngine = searchEngine
        self.requestDelay = requestDelay
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.researchConfiguration = researchConfiguration
    }

    /// The default configuration.
    public static let `default` = CrawlerConfiguration()
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
