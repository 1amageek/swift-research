import Foundation
@testable import SwiftResearch

extension ResearchAgent.Result {
    /// Converts to `AggregatedResult` for compatibility with the Evaluation framework.
    public func toAggregatedResult() -> AggregatedResult {
        AggregatedResult(
            objective: objective,
            questions: [],
            successCriteria: [],
            reviewedContents: [],
            responseMarkdown: answer,
            keywordsUsed: [],
            statistics: AggregatedStatistics(
                totalPagesVisited: visitedURLs.count,
                relevantPagesFound: visitedURLs.count,
                keywordsUsed: 0,
                duration: duration
            )
        )
    }
}
