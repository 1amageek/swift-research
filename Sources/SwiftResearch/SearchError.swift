import Foundation

// MARK: - SearchError

/// Errors that can occur during search operations.
///
/// This enum covers all error cases that may arise during the search process,
/// including network failures, configuration issues, and operational timeouts.
///
/// ## Topics
///
/// ### Search Errors
/// - ``searchFailed(_:)``
/// - ``noURLsFound``
/// - ``invalidURL(_:)``
///
/// ### Fetch Errors
/// - ``fetchFailed(_:_:)``
/// - ``timeout``
///
/// ### Configuration Errors
/// - ``modelUnavailable``
/// - ``invalidConfiguration(_:)``
///
/// ### Operational Errors
/// - ``cancelled``
public enum SearchError: Error, Sendable {
    /// Search operation failed with the specified message.
    case searchFailed(String)

    /// Failed to fetch content from the specified URL.
    case fetchFailed(URL, String)

    /// The language model is not available.
    case modelUnavailable

    /// Invalid configuration with the specified details.
    case invalidConfiguration(String)

    /// The operation timed out.
    case timeout

    /// No URLs were found in the search results.
    case noURLsFound

    /// The specified URL string is invalid.
    case invalidURL(String)

    /// The operation was cancelled.
    case cancelled
}

// MARK: - LocalizedError

extension SearchError: LocalizedError {
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
