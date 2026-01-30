import Foundation
import SwiftAgent

// MARK: - StatementExtractorStep

/// A step that extracts verifiable factual statements from research output.
///
/// Uses an internal session to analyze text and extract verifiable statements
/// for fact-checking.
///
/// ```swift
/// let step = StatementExtractorStep()
/// let response = try await step
///     .context(ModelContext(model))
///     .run(ExtractionRequest(text: markdown, maxStatements: 20))
/// let statements = response.statements
/// ```
public struct StatementExtractorStep: Step, Sendable {
    public typealias Input = ExtractionRequest
    public typealias Output = StatementExtractionResponse

    @Context private var modelContext: ModelContext

    /// Creates a new statement extractor step.
    public init() {}

    public func run(_ input: ExtractionRequest) async throws -> StatementExtractionResponse {
        // Create internal session for extraction
        let session = LanguageModelSession(
            model: modelContext.model,
            tools: [],
            instructions: extractionInstructions
        )

        let response = try await session.respond(
            to: buildPrompt(input),
            generating: StatementExtractionResponse.self
        )

        return response.content
    }

    // MARK: - Private Helpers

    private var extractionInstructions: String {
        """
        あなたは事実確認のための声明抽出アシスタントです。
        与えられたテキストから検証可能な事実の声明を抽出してください。

        声明の種類（必ず小文字で出力）:
        - numeric: 数値、統計、測定値を含む主張
        - temporal: 日付、期間、時系列に関する主張
        - entity: 特定の実体や関係に関する主張
        - causal: 因果関係に関する主張
        - comparative: 比較に関する主張

        抽出する声明は以下の基準を満たすこと:
        - 外部ソースで検証可能な具体的事実
        - 意見や予測ではない客観的な主張
        - 研究の主要な発見に関連する重要な声明
        """
    }

    private func buildPrompt(_ input: ExtractionRequest) -> String {
        """
        以下のテキストから検証可能な事実の声明を最大\(input.maxStatements)件抽出してください。

        各声明について:
        - text: ドキュメントから抽出した正確なテキスト
        - type: 声明の種類（numeric, temporal, entity, causal, comparative のいずれか、必ず小文字）
        - sourceSection: 声明が出現するセクション名
        - verifiabilityConfidence: 検証可能性の確信度 (0.0-1.0)
        - suggestedSearchQuery: 検証のための推奨検索クエリ

        対象テキスト:
        ---
        \(input.text.prefix(10000))
        ---

        重要な声明を優先して抽出してください。
        """
    }
}

// MARK: - Convenience Extensions

extension StatementExtractorStep {
    /// Extracts statements and converts to VerifiableStatement array.
    ///
    /// - Parameters:
    ///   - text: The text to extract statements from.
    ///   - maxStatements: Maximum number of statements to extract.
    /// - Returns: Array of verifiable statements.
    public func extract(from text: String, maxStatements: Int = 20) async throws -> [VerifiableStatement] {
        let response = try await run(ExtractionRequest(text: text, maxStatements: maxStatements))

        return response.statements.prefix(maxStatements).map { extracted in
            VerifiableStatement(
                text: extracted.text,
                type: extracted.type,
                sourceSection: extracted.sourceSection,
                verifiabilityConfidence: extracted.verifiabilityConfidence,
                suggestedSearchQuery: extracted.suggestedSearchQuery.isEmpty ? nil : extracted.suggestedSearchQuery
            )
        }
    }
}
