import Foundation

/// Progress update during crawling operations.
///
/// Use this to track real-time progress of research operations.
public enum CrawlProgress: Sendable {
    /// Research has started with the given objective.
    case started(objective: String)

    /// Phase changed.
    case phaseChanged(phase: ResearchPhase)

    /// Keywords were generated from objective analysis.
    case keywordsGenerated(keywords: [String])

    /// Search started for a keyword.
    case searchStarted(keyword: String)

    /// URLs were found from search.
    case urlsFound(keyword: String, urls: [URL])

    /// URL processing started.
    case urlProcessingStarted(url: URL)

    /// URL processing completed with result.
    case urlProcessed(result: URLProcessResult)

    /// Sufficiency check completed.
    case sufficiencyChecked(isSufficient: Bool, reason: String)

    /// Additional keywords added.
    case additionalKeywords(keywords: [String])

    /// Response building started.
    case buildingResponse

    /// Prompt was sent to LLM (for debugging).
    case promptSent(phase: String, prompt: String)

    /// Research completed.
    case completed(statistics: AggregatedStatistics)

    /// Error occurred.
    case error(message: String)
}

/// Research phase indicator.
public enum ResearchPhase: String, Sendable, CaseIterable {
    case analyzing = "Analyzing Objective"
    case searching = "Searching"
    case reviewing = "Reviewing Content"
    case checkingSufficiency = "Checking Sufficiency"
    case buildingResponse = "Building Response"
    case completed = "Completed"
}

/// Result of processing a single URL.
public struct URLProcessResult: Sendable {
    /// The processed URL.
    public let url: URL
    /// Page title if available.
    public let title: String?
    /// Extracted information.
    public let extractedInfo: String
    /// Whether the content was relevant.
    public let isRelevant: Bool
    /// Processing duration in seconds.
    public let duration: TimeInterval
    /// Status of the processing.
    public let status: URLStatus

    public init(
        url: URL,
        title: String?,
        extractedInfo: String,
        isRelevant: Bool,
        duration: TimeInterval,
        status: URLStatus
    ) {
        self.url = url
        self.title = title
        self.extractedInfo = extractedInfo
        self.isRelevant = isRelevant
        self.duration = duration
        self.status = status
    }
}

/// Status of URL processing.
public enum URLStatus: String, Sendable {
    case success = "Success"
    case failed = "Failed"
    case timeout = "Timeout"
    case skipped = "Skipped"
}

/// Type alias for progress stream.
public typealias CrawlProgressStream = AsyncStream<CrawlProgress>
