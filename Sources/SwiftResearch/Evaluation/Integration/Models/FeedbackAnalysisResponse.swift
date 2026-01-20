import Foundation
import SwiftAgent

// MARK: - Enums for Feedback Analysis

/// Priority level for improvement suggestions.
@Generable
public enum ImprovementPriority: String, Sendable, Codable, CaseIterable {
    case high = "high"
    case medium = "medium"
    case low = "low"
}

/// Category of diagnosed weakness.
@Generable
public enum WeaknessCategory: String, Sendable, Codable, CaseIterable {
    case coverage = "coverage"
    case insight = "insight"
    case accuracy = "accuracy"
    case clarity = "clarity"
    case relevance = "relevance"
}

/// Phase affected by a weakness.
@Generable
public enum AffectedPhase: String, Sendable, Codable, CaseIterable {
    case phase1 = "phase1"
    case phase3 = "phase3"
    case phase4 = "phase4"
    case phase5 = "phase5"
}

// MARK: - Feedback Analysis Response

/// Response from feedback analysis.
///
/// The LLM analyzes evaluation results to identify areas for improvement.
@Generable
public struct FeedbackAnalysisResponse: Sendable {
    @Guide(description: "Phase 1（目的分析）の改善提案")
    public let phase1Improvements: [ImprovementSuggestion]

    @Guide(description: "Phase 3（コンテンツレビュー）の改善提案")
    public let phase3Improvements: [ImprovementSuggestion]

    @Guide(description: "Phase 4（十分性チェック）の改善提案")
    public let phase4Improvements: [ImprovementSuggestion]

    @Guide(description: "Phase 5（レスポンス生成）の改善提案")
    public let phase5Improvements: [ImprovementSuggestion]

    @Guide(description: "全体的な分析サマリー")
    public let overallSummary: String
}

/// Individual improvement suggestion.
@Generable
public struct ImprovementSuggestion: Sendable {
    @Guide(description: "改善対象のパラメータまたはプロンプト要素")
    public let target: String

    @Guide(description: "現在の問題点")
    public let currentIssue: String

    @Guide(description: "提案する改善内容")
    public let suggestedChange: String

    @Guide(description: "期待される改善効果（0.0〜1.0）", .range(0.0...1.0))
    public let expectedImpact: Double

    @Guide(description: "改善の優先度")
    public let priority: ImprovementPriority
}

// MARK: - Parameter Adjustment Response

/// Response from parameter adjustment.
///
/// The LLM suggests specific parameter values based on feedback analysis.
@Generable
public struct ParameterAdjustmentResponse: Sendable {
    @Guide(description: "調整するパラメータのリスト")
    public let adjustments: [ParameterAdjustment]

    @Guide(description: "調整の全体的な根拠")
    public let rationale: String
}

/// Individual parameter adjustment.
@Generable
public struct ParameterAdjustment: Sendable {
    @Guide(description: "パラメータ名")
    public let parameterName: String

    @Guide(description: "現在の値")
    public let currentValue: String

    @Guide(description: "提案する新しい値")
    public let suggestedValue: String

    @Guide(description: "変更理由")
    public let reason: String
}

// MARK: - Weakness Diagnosis Response

/// Response from weakness diagnosis.
///
/// The LLM diagnoses the root cause of low scores.
@Generable
public struct WeaknessDiagnosisResponse: Sendable {
    @Guide(description: "検出された弱点のリスト")
    public let weaknesses: [DiagnosedWeakness]

    @Guide(description: "弱点間の関連性の分析")
    public let correlationAnalysis: String
}

/// Individual diagnosed weakness.
@Generable
public struct DiagnosedWeakness: Sendable {
    @Guide(description: "弱点のカテゴリ")
    public let category: WeaknessCategory

    @Guide(description: "弱点の具体的な説明")
    public let weaknessDescription: String

    @Guide(description: "根本原因の推定")
    public let rootCause: String

    @Guide(description: "影響を受けているPhase")
    public let affectedPhase: AffectedPhase

    @Guide(description: "深刻度（0.0〜1.0）", .range(0.0...1.0))
    public let severity: Double
}
