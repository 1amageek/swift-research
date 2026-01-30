import Foundation

// MARK: - ReviewedContent

/// Reviewed content from a web page.
public struct ReviewedContent: Sendable {
    /// The URL of the reviewed content.
    public let url: URL
    /// The page title, if available.
    public let title: String?
    /// Extracted relevant information (concise).
    public let extractedInfo: String
    /// Whether the content is relevant.
    public let isRelevant: Bool
    /// Line ranges where relevant information is located.
    public let relevantRanges: [Range<Int>]
    /// Actual text excerpts extracted from the relevant ranges.
    public let excerpts: [String]

    public init(
        url: URL,
        title: String?,
        extractedInfo: String,
        isRelevant: Bool,
        relevantRanges: [Range<Int>] = [],
        excerpts: [String] = []
    ) {
        self.url = url
        self.title = title
        self.extractedInfo = extractedInfo
        self.isRelevant = isRelevant
        self.relevantRanges = relevantRanges
        self.excerpts = excerpts
    }
}

// MARK: - AggregatedResult

/// Aggregated research result.
///
/// Used by the Evaluation framework to assess research quality.
public struct AggregatedResult: Sendable {
    /// The original research objective.
    public let objective: String
    /// Questions generated during research.
    public let questions: [String]
    /// Success criteria for the research.
    public let successCriteria: [String]
    /// Reviewed contents from research.
    public let reviewedContents: [ReviewedContent]
    /// Final response in Markdown format.
    public let responseMarkdown: String
    /// Keywords used during search.
    public let keywordsUsed: [String]
    /// Aggregated statistics.
    public let statistics: AggregatedStatistics

    public init(
        objective: String,
        questions: [String],
        successCriteria: [String],
        reviewedContents: [ReviewedContent],
        responseMarkdown: String,
        keywordsUsed: [String],
        statistics: AggregatedStatistics
    ) {
        self.objective = objective
        self.questions = questions
        self.successCriteria = successCriteria
        self.reviewedContents = reviewedContents
        self.responseMarkdown = responseMarkdown
        self.keywordsUsed = keywordsUsed
        self.statistics = statistics
    }
}

// MARK: - AggregatedStatistics

/// Aggregated statistics from a research session.
public struct AggregatedStatistics: Sendable {
    /// Total number of pages visited.
    public let totalPagesVisited: Int
    /// Number of relevant pages found.
    public let relevantPagesFound: Int
    /// Number of keywords used.
    public let keywordsUsed: Int
    /// Total duration of the research.
    public let duration: Duration

    public init(
        totalPagesVisited: Int,
        relevantPagesFound: Int,
        keywordsUsed: Int,
        duration: Duration
    ) {
        self.totalPagesVisited = totalPagesVisited
        self.relevantPagesFound = relevantPagesFound
        self.keywordsUsed = keywordsUsed
        self.duration = duration
    }
}
