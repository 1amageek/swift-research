import Foundation

/// クローリングの結果を表す構造体
public struct CrawlerResult: Sendable {
    public let objective: String
    public let contents: [CrawledContent]
    public let summary: String?
    public let completionReason: CompletionReason
    public let statistics: CrawlStatistics

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

/// クローリング完了理由
public enum CompletionReason: Sendable {
    case objectiveAchieved      // 目的達成
    case noMoreLinks            // 辿るリンクがない
    case cancelled              // キャンセルされた
    case error(String)          // エラー発生
}

/// クローリング統計情報
public struct CrawlStatistics: Sendable {
    public let totalPagesVisited: Int
    public let totalLinksFound: Int
    public let duration: Duration
    public let startedAt: Date
    public let completedAt: Date

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
