import Foundation

/// クローラーのエラー
public enum CrawlerError: Error, Sendable {
    case searchFailed(String)
    case fetchFailed(URL, String)
    case modelUnavailable
    case invalidConfiguration(String)
    case timeout
    case noURLsFound
    case invalidURL(String)
    case cancelled
}

extension CrawlerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .searchFailed(let message):
            return "Search failed: \(message)"
        case .fetchFailed(let url, let message):
            return "Failed to fetch \(url): \(message)"
        case .modelUnavailable:
            return "Language model is not available"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .timeout:
            return "Operation timed out"
        case .noURLsFound:
            return "No URLs found"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}
