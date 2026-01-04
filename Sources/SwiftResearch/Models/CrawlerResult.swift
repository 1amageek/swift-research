import Foundation

// MARK: - CrawlerResult

/// The result of a crawling session.
///
/// Contains all collected content, the final summary, and statistics
/// about the crawling process.
///
/// ## Topics
///
/// ### Properties
/// - ``objective``
/// - ``contents``
/// - ``summary``
/// - ``completionReason``
/// - ``statistics``
public struct CrawlerResult: Sendable {
    /// The original research objective.
    public let objective: String

    /// The crawled content items.
    public let contents: [CrawledContent]

    /// The generated summary, if available.
    public let summary: String?

    /// The reason why crawling completed.
    public let completionReason: CompletionReason

    /// Statistics about the crawling session.
    public let statistics: CrawlStatistics

    /// Creates a new crawler result.
    ///
    /// - Parameters:
    ///   - objective: The original research objective.
    ///   - contents: The crawled content items.
    ///   - summary: The generated summary, if available.
    ///   - completionReason: The reason why crawling completed.
    ///   - statistics: Statistics about the crawling session.
    public init(
        objective: String,
        contents: [CrawledContent],
        summary: String? = nil,
        completionReason: CompletionReason,
        statistics: CrawlStatistics
    ) {
        self.objective = objective
        self.contents = contents
        self.summary = summary
        self.completionReason = completionReason
        self.statistics = statistics
    }
}

// MARK: - CompletionReason

/// The reason why a crawling session completed.
///
/// ## Topics
///
/// ### Success Cases
/// - ``objectiveAchieved``
/// - ``noMoreLinks``
///
/// ### Failure Cases
/// - ``cancelled``
/// - ``error(_:)``
public enum CompletionReason: Sendable {
    /// The research objective was achieved.
    case objectiveAchieved

    /// No more links are available to follow.
    case noMoreLinks

    /// The operation was cancelled by the user.
    case cancelled

    /// An error occurred during crawling.
    case error(String)
}

// MARK: - CrawlStatistics

/// Statistics about a crawling session.
///
/// Provides metrics about pages visited, links discovered, and timing information.
///
/// ## Topics
///
/// ### Page Metrics
/// - ``totalPagesVisited``
/// - ``totalLinksFound``
///
/// ### Timing
/// - ``duration``
/// - ``startedAt``
/// - ``completedAt``
public struct CrawlStatistics: Sendable {
    /// The total number of pages visited.
    public let totalPagesVisited: Int

    /// The total number of links discovered.
    public let totalLinksFound: Int

    /// The total duration of the crawling session.
    public let duration: Duration

    /// The timestamp when crawling started.
    public let startedAt: Date

    /// The timestamp when crawling completed.
    public let completedAt: Date

    /// Creates new crawl statistics.
    ///
    /// - Parameters:
    ///   - totalPagesVisited: The total number of pages visited.
    ///   - totalLinksFound: The total number of links discovered.
    ///   - duration: The total duration of the crawling session.
    ///   - startedAt: The timestamp when crawling started.
    ///   - completedAt: The timestamp when crawling completed.
    public init(
        totalPagesVisited: Int,
        totalLinksFound: Int,
        duration: Duration,
        startedAt: Date,
        completedAt: Date
    ) {
        self.totalPagesVisited = totalPagesVisited
        self.totalLinksFound = totalLinksFound
        self.duration = duration
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}
