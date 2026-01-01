import Foundation

/// クローラーへの入力
public struct CrawlerInput: Sendable {
    public let urls: [URL]
    public let objective: String

    public init(
        urls: [URL],
        objective: String
    ) {
        self.urls = urls
        self.objective = objective
    }
}

/// クローラーの設定
public struct CrawlerConfiguration: Sendable {
    public let searchEngine: SearchEngine
    public let maxSearchResults: Int
    public let requestDelay: Duration
    public let modelName: String
    public let baseURL: URL
    public let timeout: TimeInterval
    public let allowedDomains: [String]?
    public let blockedDomains: [String]

    public init(
        searchEngine: SearchEngine = .duckDuckGo,
        maxSearchResults: Int = 5,
        requestDelay: Duration = .milliseconds(500),
        modelName: String = "gpt-oss:20b",
        baseURL: URL = URL(string: "http://127.0.0.1:11434")!,
        timeout: TimeInterval = 300.0,
        allowedDomains: [String]? = nil,
        blockedDomains: [String] = []
    ) {
        self.searchEngine = searchEngine
        self.maxSearchResults = maxSearchResults
        self.requestDelay = requestDelay
        self.modelName = modelName
        self.baseURL = baseURL
        self.timeout = timeout
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
    }

    public static let `default` = CrawlerConfiguration()
}

/// 検索エンジン
public enum SearchEngine: Sendable {
    case duckDuckGo
    case google
    case bing

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

    public func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        let urlString = String(format: searchURLTemplate, encoded)
        return URL(string: urlString)
    }
}
