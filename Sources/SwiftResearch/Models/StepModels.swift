import Foundation

// MARK: - Phase 1: Objective Analysis Result

/// Internal result of objective analysis (non-Generable struct).
///
/// Reference: AMD Framework (arXiv:2502.08557) - Socratic questioning decomposition
public struct ObjectiveAnalysis: Sendable {
    /// Search keywords extracted from the objective.
    public let keywords: [String]
    /// Socratic questions (clarification, assumption testing, implication exploration).
    public let questions: [String]
    /// Criteria for determining sufficient information.
    public let successCriteria: [String]

    public init(
        keywords: [String],
        questions: [String],
        successCriteria: [String]
    ) {
        self.keywords = keywords
        self.questions = questions
        self.successCriteria = successCriteria
    }

    /// Converts from ObjectiveAnalysisResponse.
    public init(from response: ObjectiveAnalysisResponse) {
        self.keywords = response.keywords
        self.questions = response.questions
        self.successCriteria = response.successCriteria
    }

    /// Creates a fallback analysis when LLM fails.
    public static func fallback(objective: String) -> ObjectiveAnalysis {
        ObjectiveAnalysis(
            keywords: [objective],
            questions: [objective],
            successCriteria: ["Find relevant information"]
        )
    }
}

// MARK: - Phase 3: Content Review Result

/// Internal result of content review (non-Generable struct).
///
/// Focuses on information extraction. Question verification is performed in Phase 4.
public struct ContentReview: Sendable {
    /// Whether the content is relevant to the objective.
    public let isRelevant: Bool
    /// Extracted relevant information.
    public let extractedInfo: String
    /// Whether deep crawling should be performed.
    public let shouldDeepCrawl: Bool
    /// Priority links for deep crawling.
    public let priorityLinks: [PriorityLink]

    public init(
        isRelevant: Bool,
        extractedInfo: String,
        shouldDeepCrawl: Bool,
        priorityLinks: [PriorityLink]
    ) {
        self.isRelevant = isRelevant
        self.extractedInfo = extractedInfo
        self.shouldDeepCrawl = shouldDeepCrawl
        self.priorityLinks = priorityLinks
    }

    /// Converts from ContentReviewResponse.
    public init(from response: ContentReviewResponse) {
        self.isRelevant = response.isRelevant
        self.extractedInfo = response.extractedInfo
        self.shouldDeepCrawl = response.shouldDeepCrawl
        self.priorityLinks = response.priorityLinks
    }

    /// Creates a fallback as irrelevant content.
    public static func irrelevant() -> ContentReview {
        ContentReview(
            isRelevant: false,
            extractedInfo: "",
            shouldDeepCrawl: false,
            priorityLinks: []
        )
    }
}

// MARK: - ReviewedContent

/// Reviewed content output from Phase 3.
///
/// Contains only extraction results. Question verification is performed in Phase 4.
public struct ReviewedContent: Sendable {
    /// The URL of the reviewed content.
    public let url: URL
    /// The page title, if available.
    public let title: String?
    /// Extracted relevant information (concise).
    public let extractedInfo: String
    /// Whether the content is relevant.
    public let isRelevant: Bool

    public init(
        url: URL,
        title: String?,
        extractedInfo: String,
        isRelevant: Bool
    ) {
        self.url = url
        self.title = title
        self.extractedInfo = extractedInfo
        self.isRelevant = isRelevant
    }
}

// MARK: - Internal Sufficiency Result

/// Internal result of sufficiency check (non-Generable struct).
public struct SufficiencyResult: Sendable {
    /// Whether sufficient information has been collected.
    public let isSufficient: Bool
    /// Whether further information gathering is futile.
    public let shouldGiveUp: Bool
    /// Additional keywords to search if insufficient.
    public let additionalKeywords: [String]
    /// Reason for the decision in Markdown format.
    public let reasonMarkdown: String

    public init(
        isSufficient: Bool,
        shouldGiveUp: Bool = false,
        additionalKeywords: [String] = [],
        reasonMarkdown: String = ""
    ) {
        self.isSufficient = isSufficient
        self.shouldGiveUp = shouldGiveUp
        self.additionalKeywords = additionalKeywords
        self.reasonMarkdown = reasonMarkdown
    }

    /// Converts from SufficiencyCheckResponse.
    public init(from response: SufficiencyCheckResponse) {
        self.isSufficient = response.isSufficient
        self.shouldGiveUp = response.shouldGiveUp
        self.additionalKeywords = response.additionalKeywords
        self.reasonMarkdown = response.reasonMarkdown
    }

    /// Creates an insufficient result.
    public static func insufficient(reason: String) -> SufficiencyResult {
        SufficiencyResult(
            isSufficient: false,
            shouldGiveUp: false,
            additionalKeywords: [],
            reasonMarkdown: reason
        )
    }

    /// Creates a give-up result.
    public static func giveUp(reason: String) -> SufficiencyResult {
        SufficiencyResult(
            isSufficient: false,
            shouldGiveUp: true,
            additionalKeywords: [],
            reasonMarkdown: reason
        )
    }
}

// MARK: - SearchOrchestratorStep Models

/// Input for the search orchestrator.
public struct SearchQuery: Sendable {
    /// The research objective.
    public let objective: String
    /// Maximum number of URLs to visit (safety limit).
    public let maxVisitedURLs: Int

    public init(objective: String, maxVisitedURLs: Int = 100) {
        self.objective = objective
        self.maxVisitedURLs = maxVisitedURLs
    }
}

/// Output from the search orchestrator (aggregated result).
public struct AggregatedResult: Sendable {
    /// The original research objective.
    public let objective: String
    /// Socratic questions from Phase 1.
    public let questions: [String]
    /// Success criteria from Phase 1.
    public let successCriteria: [String]
    /// Reviewed contents from Phase 3.
    public let reviewedContents: [ReviewedContent]
    /// Final response from Phase 5.
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

/// Aggregated statistics from the research session.
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
