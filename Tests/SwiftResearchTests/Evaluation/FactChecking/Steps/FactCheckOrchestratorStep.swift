import Foundation
import SwiftAgent
@testable import SwiftResearch

// MARK: - Input

/// Input for fact checking orchestration.
public struct FactCheckInput: Sendable {
    /// The research output to fact-check.
    public let researchOutput: String

    /// Maximum number of statements to verify.
    public let maxStatements: Int

    /// Number of evidence pieces per statement.
    public let evidencePerStatement: Int

    /// Minimum confidence threshold for verification.
    public let confidenceThreshold: Double

    /// Creates a new fact check input.
    ///
    /// - Parameters:
    ///   - researchOutput: The research output markdown.
    ///   - maxStatements: Maximum statements to verify.
    ///   - evidencePerStatement: Evidence pieces per statement.
    ///   - confidenceThreshold: Minimum confidence for verification.
    public init(
        researchOutput: String,
        maxStatements: Int = 20,
        evidencePerStatement: Int = 3,
        confidenceThreshold: Double = 0.7
    ) {
        self.researchOutput = researchOutput
        self.maxStatements = maxStatements
        self.evidencePerStatement = evidencePerStatement
        self.confidenceThreshold = confidenceThreshold
    }
}

// MARK: - FactCheckOrchestratorStep

/// A step that orchestrates the complete fact-checking pipeline.
///
/// This step:
/// 1. Extracts verifiable statements from research output
/// 2. Retrieves evidence for each statement
/// 3. Verifies each statement based on evidence
/// 4. Aggregates results into a comprehensive fact-check report
///
/// Each child step creates its own internal session for LLM calls.
///
/// ```swift
/// let step = FactCheckOrchestratorStep()
/// let result = try await step
///     .context(ModelContext(model))
///     .context(crawlerConfig)
///     .run(FactCheckInput(researchOutput: markdown))
/// ```
public struct FactCheckOrchestratorStep: Step, Sendable {
    public typealias Input = FactCheckInput
    public typealias Output = FactCheckResult

    @Context private var modelContext: ModelContext
    @Context private var crawlerConfig: SearchConfiguration

    /// Creates a new fact check orchestrator step.
    public init() {}

    public func run(_ input: FactCheckInput) async throws -> FactCheckResult {
        // Step 1: Extract verifiable statements
        let extractorStep = StatementExtractorStep()
            .context(modelContext)

        let extractionResponse = try await extractorStep.run(
            ExtractionRequest(text: input.researchOutput, maxStatements: input.maxStatements)
        )

        let statements = extractionResponse.statements.prefix(input.maxStatements).map { extracted in
            VerifiableStatement(
                text: extracted.text,
                type: extracted.type,
                sourceSection: extracted.sourceSection,
                verifiabilityConfidence: extracted.verifiabilityConfidence,
                suggestedSearchQuery: extracted.suggestedSearchQuery.isEmpty ? nil : extracted.suggestedSearchQuery
            )
        }

        // Step 2 & 3: Retrieve evidence and verify each statement
        let verifications = try await verifyStatements(
            statements,
            input: input
        )

        // Step 4: Aggregate results
        return FactCheckResult(verifications: verifications)
    }

    private func verifyStatements(
        _ statements: [VerifiableStatement],
        input: FactCheckInput
    ) async throws -> [FactVerificationResult] {
        // Process statements sequentially
        var results: [FactVerificationResult] = []

        for statement in statements {
            let evidenceRetriever = EvidenceRetrievalStep()
                .context(modelContext)
                .context(crawlerConfig)

            let verifier = FactVerifierStep()
                .context(modelContext)

            do {
                // Retrieve evidence
                let evidence = try await evidenceRetriever.run(
                    EvidenceRetrievalInput(
                        statement: statement,
                        evidenceCount: input.evidencePerStatement
                    )
                )

                // Verify statement
                let result = try await verifier.run(
                    FactVerificationInput(
                        statement: statement,
                        evidence: evidence,
                        confidenceThreshold: input.confidenceThreshold
                    )
                )

                results.append(result)
            } catch {
                // Return error result when verification fails
                results.append(FactVerificationResult(
                    statement: statement,
                    verdict: .errorOccurred,
                    evidence: [],
                    confidence: 0.0,
                    explanation: "Verification failed: \(error.localizedDescription)",
                    correction: nil
                ))
            }
        }

        return results
    }
}

// MARK: - Convenience Extensions

extension FactCheckOrchestratorStep {
    /// Fact-checks research output with default settings.
    ///
    /// - Parameter researchOutput: The research output to verify.
    /// - Returns: Fact check result.
    public func check(_ researchOutput: String) async throws -> FactCheckResult {
        try await run(FactCheckInput(researchOutput: researchOutput))
    }
}
