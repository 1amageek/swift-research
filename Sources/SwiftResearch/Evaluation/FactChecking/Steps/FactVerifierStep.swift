import Foundation
import SwiftAgent

// MARK: - Input

/// Input for fact verification.
public struct FactVerificationInput: Sendable {
    /// The statement to verify.
    public let statement: VerifiableStatement

    /// Evidence collected for verification.
    public let evidence: [Evidence]

    /// Minimum confidence threshold for verification.
    public let confidenceThreshold: Double

    /// Creates a new fact verification input.
    ///
    /// - Parameters:
    ///   - statement: The statement to verify.
    ///   - evidence: Collected evidence.
    ///   - confidenceThreshold: Minimum confidence for verification.
    public init(
        statement: VerifiableStatement,
        evidence: [Evidence],
        confidenceThreshold: Double = 0.7
    ) {
        self.statement = statement
        self.evidence = evidence
        self.confidenceThreshold = confidenceThreshold
    }
}

// MARK: - FactVerifierStep

/// A step that verifies a statement based on collected evidence.
///
/// Analyzes the evidence to determine if the statement is correct, incorrect,
/// partially correct, or unknown. Provides confidence scores and explanations.
///
/// ```swift
/// let step = FactVerifierStep()
/// let result = try await step
///     .context(ModelContext(model))
///     .run(FactVerificationInput(statement: statement, evidence: evidence))
/// ```
public struct FactVerifierStep: Step, Sendable {
    public typealias Input = FactVerificationInput
    public typealias Output = FactVerificationResult

    @Context private var modelContext: ModelContext

    /// Creates a new fact verifier step.
    public init() {}

    public func run(_ input: FactVerificationInput) async throws -> FactVerificationResult {
        // If no evidence, return unknown
        if input.evidence.isEmpty {
            return FactVerificationResult(
                statement: input.statement,
                verdict: .unknown,
                evidence: [],
                confidence: 0.0,
                explanation: "No evidence was found to verify this statement."
            )
        }

        // Create internal session for verification
        let session = LanguageModelSession(
            model: modelContext.model,
            tools: [],
            instructions: verificationInstructions
        )

        let prompt = buildPrompt(for: input)

        let response = try await session.respond(
            to: prompt,
            generating: FactVerificationResponse.self
        )

        let verificationResult = response.content

        // Only include correction if verdict indicates an error
        let correction: String? = switch verificationResult.verdict {
        case .incorrect, .partiallyCorrect:
            verificationResult.correction.isEmpty ? nil : verificationResult.correction
        case .correct, .unknown, .errorOccurred:
            nil
        }

        return FactVerificationResult(
            statement: input.statement,
            verdict: verificationResult.verdict,
            evidence: input.evidence,
            confidence: verificationResult.confidence,
            explanation: verificationResult.explanation,
            correction: correction
        )
    }

    private var verificationInstructions: String {
        """
        あなたは事実検証アシスタントです。
        収集された証拠に基づいて声明の正確性を判断してください。

        判定基準:
        - correct: 証拠が声明を強く支持している
        - incorrect: 証拠が声明を明確に否定している
        - partiallyCorrect: 声明は概ね正しいが不正確な部分がある
        - unknown: 証拠が不十分または矛盾している

        確信度基準:
        - 0.9以上: 複数の高信頼性ソースが一致
        - 0.7-0.9: 少なくとも1つの高信頼性ソースが支持
        - 0.5-0.7: 証拠が混在または中程度の信頼性
        - 0.5未満: 証拠が弱いまたは矛盾
        """
    }

    private func buildPrompt(for input: FactVerificationInput) -> String {
        let evidenceText = input.evidence.enumerated().map { index, evidence in
            """
            証拠 \(index + 1):
            - ソース: \(evidence.sourceTitle) (\(evidence.sourceURL))
            - 支持レベル: \(evidence.supportLevel.rawValue)
            - 信頼性: \(String(format: "%.2f", evidence.sourceCredibility))
            - 関連テキスト: \(evidence.relevantText)
            """
        }.joined(separator: "\n\n")

        return """
        収集された証拠に基づいて以下の声明を検証してください。

        検証対象の声明:
        "\(input.statement.text)"
        種類: \(input.statement.type.rawValue)

        収集された証拠:
        \(evidenceText)

        判断項目:
        1. 声明は正しいか、誤りか、部分的に正しいか、不明か
        2. この判定に対する確信度 (0.0-1.0)
        3. 証拠に基づいた推論の説明
        4. 誤りまたは部分的に正しい場合、正しい情報は何か
        """
    }
}

// MARK: - Convenience Extensions

extension FactVerifierStep {
    /// Verifies a statement with its evidence.
    ///
    /// - Parameters:
    ///   - statement: The statement to verify.
    ///   - evidence: Collected evidence.
    /// - Returns: Verification result.
    public func verify(
        _ statement: VerifiableStatement,
        with evidence: [Evidence]
    ) async throws -> FactVerificationResult {
        try await run(FactVerificationInput(statement: statement, evidence: evidence))
    }
}
