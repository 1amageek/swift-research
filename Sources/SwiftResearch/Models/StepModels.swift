import Foundation

// MARK: - Phase 1: Objective Analysis Result

/// 目的分析の内部結果（@Generableではない通常の構造体）
/// 参考: AMD Framework (arXiv:2502.08557) - ソクラテス的質問による分解
public struct ObjectiveAnalysis: Sendable {
    public let keywords: [String]
    public let questions: [String]        // ソクラテス的質問（明確化・前提検証・含意探索）
    public let successCriteria: [String]  // 充足判定条件

    public init(
        keywords: [String],
        questions: [String],
        successCriteria: [String]
    ) {
        self.keywords = keywords
        self.questions = questions
        self.successCriteria = successCriteria
    }

    /// ObjectiveAnalysisResponseから変換
    public init(from response: ObjectiveAnalysisResponse) {
        self.keywords = response.keywords
        self.questions = response.questions
        self.successCriteria = response.successCriteria
    }

    /// フォールバック用
    public static func fallback(objective: String) -> ObjectiveAnalysis {
        ObjectiveAnalysis(
            keywords: [objective],
            questions: [objective],
            successCriteria: ["関連情報が見つかる"]
        )
    }
}

// MARK: - Phase 3: Content Review Result

/// コンテンツレビューの内部結果（@Generableではない通常の構造体）
/// 情報抽出に集中（問い検証はPhase 4で一括実施）
public struct ContentReview: Sendable {
    public let isRelevant: Bool
    public let extractedInfo: String
    public let shouldDeepCrawl: Bool
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

    /// ContentReviewResponseから変換
    public init(from response: ContentReviewResponse) {
        self.isRelevant = response.isRelevant
        self.extractedInfo = response.extractedInfo
        self.shouldDeepCrawl = response.shouldDeepCrawl
        self.priorityLinks = response.priorityLinks
    }

    /// フォールバック（無関連として扱う）
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

/// レビュー済みコンテンツ（Phase 3の出力）
/// 情報抽出結果のみ保持（問い検証はPhase 4で実施）
public struct ReviewedContent: Sendable {
    public let url: URL
    public let title: String?
    public let extractedInfo: String  // 抽出した関連情報（簡潔）
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

/// 情報充足度の内部結果（@Generableではない通常の構造体）
public struct SufficiencyResult: Sendable {
    public let isSufficient: Bool
    public let shouldGiveUp: Bool
    public let additionalKeywords: [String]
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

    /// SufficiencyCheckResponseから変換
    public init(from response: SufficiencyCheckResponse) {
        self.isSufficient = response.isSufficient
        self.shouldGiveUp = response.shouldGiveUp
        self.additionalKeywords = response.additionalKeywords
        self.reasonMarkdown = response.reasonMarkdown
    }

    /// 不足状態のデフォルト
    public static func insufficient(reason: String) -> SufficiencyResult {
        SufficiencyResult(
            isSufficient: false,
            shouldGiveUp: false,
            additionalKeywords: [],
            reasonMarkdown: reason
        )
    }

    /// 諦め状態
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

/// 検索オーケストレーターへの入力
public struct SearchQuery: Sendable {
    public let objective: String
    /// 訪問URL数の上限（セーフティリミット）
    public let maxVisitedURLs: Int

    public init(objective: String, maxVisitedURLs: Int = 100) {
        self.objective = objective
        self.maxVisitedURLs = maxVisitedURLs
    }
}

/// 検索オーケストレーターからの出力（統合結果）
public struct AggregatedResult: Sendable {
    public let objective: String
    public let questions: [String]                 // Phase 1: ソクラテス的質問
    public let successCriteria: [String]           // Phase 1: 充足判定条件
    public let reviewedContents: [ReviewedContent] // Phase 3: レビュー済みコンテンツ
    public let responseMarkdown: String            // Phase 5: 最終応答
    public let keywordsUsed: [String]
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

/// 統合統計情報
public struct AggregatedStatistics: Sendable {
    public let totalPagesVisited: Int   // 訪問したページ総数
    public let relevantPagesFound: Int  // 関連コンテンツ数
    public let keywordsUsed: Int
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
