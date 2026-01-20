import Foundation
import SwiftAgent

// MARK: - Statement Extraction Response

/// Response from statement extraction.
///
/// The LLM extracts verifiable factual statements from the research output.
@Generable
public struct StatementExtractionResponse: Sendable {
    @Guide(description: "抽出された検証可能な文のリスト")
    public let statements: [ExtractedStatement]
}

/// Individual statement extracted by LLM.
@Generable
public struct ExtractedStatement: Sendable {
    @Guide(description: "検証可能な文（原文から抽出）")
    public let text: String

    @Guide(description: "文のタイプ")
    public let type: StatementType

    @Guide(description: "文が含まれるセクション名")
    public let sourceSection: String

    @Guide(description: "検証可能性の信頼度（0.0〜1.0）", .range(0.0...1.0))
    public let verifiabilityConfidence: Double

    @Guide(description: "検証に使用すべき検索クエリ")
    public let suggestedSearchQuery: String
}

// MARK: - Evidence Analysis Response

/// Response from evidence analysis.
///
/// The LLM analyzes how well a piece of evidence supports or contradicts a statement.
@Generable
public struct EvidenceAnalysisResponse: Sendable {
    @Guide(description: "証拠が文をどの程度支持するか")
    public let supportLevel: SupportLevel

    @Guide(description: "証拠から抽出した関連テキスト")
    public let relevantText: String

    @Guide(description: "支持/矛盾の分析理由")
    public let reasoning: String

    @Guide(description: "情報源の信頼性（0.0〜1.0）", .range(0.0...1.0))
    public let sourceCredibility: Double
}

// MARK: - Fact Verification Response

/// Response from fact verification.
///
/// The LLM makes a final verdict on a statement based on collected evidence.
@Generable
public struct FactVerificationResponse: Sendable {
    @Guide(description: "検証結果")
    public let verdict: FactVerdict

    @Guide(description: "判定の信頼度（0.0〜1.0）", .range(0.0...1.0))
    public let confidence: Double

    @Guide(description: "判定理由（証拠に基づく説明）")
    public let explanation: String

    @Guide(description: "正しい情報（incorrectまたはpartiallyCorrectの場合）")
    public let correction: String
}

// MARK: - Search Query Generation Response

/// Response from search query generation for fact verification.
@Generable
public struct VerificationSearchQueryResponse: Sendable {
    @Guide(description: "検証用検索クエリ（最大3つ）")
    public let queries: [String]

    @Guide(description: "各クエリが検証しようとしている観点")
    public let perspectives: [String]
}
