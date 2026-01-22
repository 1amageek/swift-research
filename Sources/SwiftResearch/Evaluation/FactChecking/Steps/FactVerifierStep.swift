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
///     .session(session)
///     .run(FactVerificationInput(statement: statement, evidence: evidence))
/// ```
public struct FactVerifierStep: Step, Sendable {
    public typealias Input = FactVerificationInput
    public typealias Output = FactVerificationResult

    @Session private var session: LanguageModelSession

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

        let prompt = buildPrompt(for: input)

        let generateStep = Generate<String, FactVerificationResponse>(
            session: session,
            prompt: { Prompt($0) }
        )
        let response = try await generateStep.run(prompt)

        // Only include correction if verdict indicates an error
        let correction: String? = switch response.verdict {
        case .incorrect, .partiallyCorrect:
            response.correction.isEmpty ? nil : response.correction
        case .correct, .unknown, .errorOccurred:
            nil
        }

        return FactVerificationResult(
            statement: input.statement,
            verdict: response.verdict,
            evidence: input.evidence,
            confidence: response.confidence,
            explanation: response.explanation,
            correction: correction
        )
    }

    private func buildPrompt(for input: FactVerificationInput) -> String {
        let evidenceText = input.evidence.enumerated().map { index, evidence in
            """
            Evidence \(index + 1):
            - Source: \(evidence.sourceTitle) (\(evidence.sourceURL))
            - Support Level: \(evidence.supportLevel.rawValue)
            - Credibility: \(String(format: "%.2f", evidence.sourceCredibility))
            - Relevant Text: \(evidence.relevantText)
            """
        }.joined(separator: "\n\n")

        return """
        Verify the following statement based on the collected evidence.

        Statement to Verify:
        "\(input.statement.text)"
        Type: \(input.statement.type.rawValue)

        Collected Evidence:
        \(evidenceText)

        Based on the evidence, determine:
        1. Is the statement correct, incorrect, partially correct, or unknown?
        2. What is your confidence in this verdict (0.0-1.0)?
        3. Explain your reasoning based on the evidence.
        4. If incorrect or partially correct, what is the correct information?

        Verdict Guidelines:
        - correct: Evidence strongly supports the statement
        - incorrect: Evidence clearly contradicts the statement
        - partiallyCorrect: Statement is mostly correct but has inaccuracies
        - unknown: Evidence is insufficient or conflicting

        Confidence Guidelines:
        - 0.9+: Multiple high-credibility sources agree
        - 0.7-0.9: At least one high-credibility source supports
        - 0.5-0.7: Evidence is mixed or from moderate-credibility sources
        - <0.5: Evidence is weak or conflicting

        IMPORTANT: Respond with a valid JSON object only. Do not include markdown formatting or code fences.
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
