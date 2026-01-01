import Foundation
import OpenFoundationModels

// MARK: - Phase 1: Objective Analysis

/// 目的分析レスポンス
/// LLMが目的を分析し、検索キーワードとソクラテス的質問を生成
/// 参考: AMD Framework (arXiv:2502.08557)
@Generable
public struct ObjectiveAnalysisResponse: Sendable {
    @Guide(description: "検索に使用するキーワード（英語、検索エンジン向け）")
    public let keywords: [String]

    @Guide(description: "答えるべき具体的な問い（明確化・前提検証・含意探索）")
    public let questions: [String]

    @Guide(description: "情報が十分と判断する条件")
    public let successCriteria: [String]
}

// MARK: - Phase 3: Content Review

/// コンテンツレビューレスポンス
/// 情報抽出に集中（問い検証はPhase 4で一括実施）
@Generable
public struct ContentReviewResponse: Sendable {
    @Guide(description: "このコンテンツは目的に関連があるか")
    public let isRelevant: Bool

    @Guide(description: "抽出した関連情報（簡潔に、100-300字程度）")
    public let extractedInfo: String

    @Guide(description: "さらに深掘りすべきリンクがあるか")
    public let shouldDeepCrawl: Bool

    @Guide(description: "深掘り候補のリンク（最大3件）")
    public let priorityLinks: [PriorityLink]
}

/// 優先リンク情報
@Generable
public struct PriorityLink: Sendable {
    @Guide(description: "リンクのインデックス番号（1から始まる）", .range(1...100))
    public let index: Int

    @Guide(description: "関連度スコア（0.0〜1.0）", .range(0.0...1.0))
    public let score: Double

    @Guide(description: "このリンクを選んだ理由")
    public let reason: String
}

// MARK: - Phase 3.5: DeepCrawl Review

/// DeepCrawlコンテンツレビューレスポンス
/// 履歴を考慮して続行判断を行う
@Generable
public struct DeepCrawlReviewResponse: Sendable {
    @Guide(description: "このコンテンツは目的に関連があるか")
    public let isRelevant: Bool

    @Guide(description: "抽出した関連情報（簡潔に、100-300字程度）")
    public let extractedInfo: String

    @Guide(description: "履歴を考慮して、さらにDeepCrawlを続ける価値があるか")
    public let shouldContinue: Bool

    @Guide(description: "続行/中断の判断理由")
    public let reason: String
}

// MARK: - Phase 4: Sufficiency Check

/// 情報充足度判定のレスポンス
@Generable
public struct SufficiencyCheckResponse: Sendable {
    @Guide(description: "目的を達成するのに十分な情報が集まったかどうか")
    public let isSufficient: Bool

    @Guide(description: "これ以上の情報取得は困難かどうか")
    public let shouldGiveUp: Bool

    @Guide(description: "追加で検索すべきキーワード（不十分な場合）")
    public let additionalKeywords: [String]

    @Guide(description: "判断理由（Markdown形式）")
    public let reasonMarkdown: String
}

// MARK: - Phase 5: Response Building

/// 最終応答生成のレスポンス
/// ソースURLはプログラムで追加するためLLMには生成させない
@Generable
public struct FinalResponseBuildingResponse: Sendable {
    @Guide(description: "目的に対する最終応答（Markdown形式）")
    public let responseMarkdown: String
}
