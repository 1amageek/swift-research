import Foundation
import SwiftAgent

// MARK: - Input

/// Input for statement extraction.
public struct StatementExtractionInput: Sendable {
    /// The research output to extract statements from.
    public let researchOutput: String

    /// Maximum number of statements to extract.
    public let maxStatements: Int

    /// Creates a new statement extraction input.
    ///
    /// - Parameters:
    ///   - researchOutput: The research output markdown.
    ///   - maxStatements: Maximum statements to extract.
    public init(researchOutput: String, maxStatements: Int = 20) {
        self.researchOutput = researchOutput
        self.maxStatements = maxStatements
    }
}

// MARK: - StatementExtractorStep

/// A step that extracts verifiable factual statements from research output.
///
/// Identifies statements that contain verifiable claims such as:
/// - Numeric claims (statistics, measurements, quantities)
/// - Temporal claims (dates, time periods)
/// - Entity claims (relationships, attributes)
/// - Causal claims (cause and effect)
/// - Comparative claims (comparisons between entities)
///
/// ```swift
/// let step = StatementExtractorStep()
/// let statements = try await step
///     .session(session)
///     .run(StatementExtractionInput(researchOutput: markdown, maxStatements: 20))
/// ```
public struct StatementExtractorStep: Step, Sendable {
    public typealias Input = StatementExtractionInput
    public typealias Output = [VerifiableStatement]

    @Session private var session: LanguageModelSession

    /// Creates a new statement extractor step.
    public init() {}

    public func run(_ input: StatementExtractionInput) async throws -> [VerifiableStatement] {
        print("[StatementExtractor] Building prompt...")
        let prompt = buildPrompt(for: input)
        print("[StatementExtractor] Calling LLM for statement extraction...")

        do {
            let generateStep = Generate<String, StatementExtractionResponse>(
                session: session,
                prompt: { Prompt($0) }
            )
            let response = try await generateStep.run(prompt)
            print("[StatementExtractor] LLM response received, parsing statements...")

            let statements = response.statements.prefix(input.maxStatements).map { extracted in
                VerifiableStatement(
                    text: extracted.text,
                    type: extracted.type,
                    sourceSection: extracted.sourceSection,
                    verifiabilityConfidence: extracted.verifiabilityConfidence,
                    suggestedSearchQuery: extracted.suggestedSearchQuery.isEmpty ? nil : extracted.suggestedSearchQuery
                )
            }
            print("[StatementExtractor] Successfully extracted \(statements.count) statements")
            return Array(statements)
        } catch {
            // Fallback: Return empty array if LLM parsing fails
            print("[StatementExtractor] Warning: Failed to extract statements: \(error)")
            return []
        }
    }

    private func buildPrompt(for input: StatementExtractionInput) -> String {
        """
        Extract verifiable factual statements from the following research output.

        Focus on statements that:
        1. Contain specific facts that can be verified through external sources
        2. Make claims about real-world entities, events, or data
        3. Are NOT opinions, predictions, or subjective assessments

        Statement types to identify:
        - numericClaim: Contains specific numbers, statistics, measurements
        - temporalClaim: Contains specific dates, time periods, sequences
        - entityClaim: Makes claims about specific entities or relationships
        - causalClaim: Claims cause-and-effect relationships
        - comparativeClaim: Compares entities or makes relative claims

        For each statement:
        - Extract the exact text from the document
        - Identify the statement type
        - Note which section it appears in
        - Estimate how confident you are it can be verified (0.0-1.0)
        - Suggest a search query for verification

        Research Output:
        ---
        \(input.researchOutput.prefix(10000))
        ---

        Extract up to \(input.maxStatements) most important verifiable statements.
        Prioritize statements that are central to the research findings.

        IMPORTANT: Respond with a valid JSON object only. Do not include markdown formatting or code fences.
        """
    }
}

// MARK: - Convenience Extensions

extension StatementExtractorStep {
    /// Extracts statements with default settings.
    ///
    /// - Parameter researchOutput: The research output to analyze.
    /// - Returns: Extracted verifiable statements.
    public func extract(from researchOutput: String) async throws -> [VerifiableStatement] {
        try await run(StatementExtractionInput(researchOutput: researchOutput))
    }
}
