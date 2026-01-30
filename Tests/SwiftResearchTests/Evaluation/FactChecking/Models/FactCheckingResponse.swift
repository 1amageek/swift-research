import Foundation
import SwiftAgent

// MARK: - Statement Extraction Response

/// Response from statement extraction.
///
/// The LLM extracts verifiable factual statements from the research output.
@Generable
public struct StatementExtractionResponse: Sendable {
    @Guide(description: "List of extracted verifiable statements")
    public let statements: [ExtractedStatement]
}

/// Individual statement extracted by LLM.
@Generable
public struct ExtractedStatement: Sendable {
    @Guide(description: "Verifiable statement (extracted from source)")
    public let text: String

    @Guide(description: "Type of statement")
    public let type: StatementType

    @Guide(description: "Section name where the statement appears")
    public let sourceSection: String

    @Guide(description: "Confidence in verifiability (0.0-1.0)", .range(0.0...1.0))
    public let verifiabilityConfidence: Double

    @Guide(description: "Suggested search query for verification")
    public let suggestedSearchQuery: String
}

// MARK: - Evidence Analysis Response

/// Response from evidence analysis.
///
/// The LLM analyzes how well a piece of evidence supports or contradicts a statement.
@Generable
public struct EvidenceAnalysisResponse: Sendable {
    @Guide(description: "How well the evidence supports the statement")
    public let supportLevel: SupportLevel

    @Guide(description: "Relevant text extracted from the evidence")
    public let relevantText: String

    @Guide(description: "Reasoning for support/contradiction")
    public let reasoning: String

    @Guide(description: "Credibility of the source (0.0-1.0)", .range(0.0...1.0))
    public let sourceCredibility: Double
}

// MARK: - Fact Verification Response

/// Response from fact verification.
///
/// The LLM makes a final verdict on a statement based on collected evidence.
@Generable
public struct FactVerificationResponse: Sendable {
    @Guide(description: "Verification verdict")
    public let verdict: FactVerdict

    @Guide(description: "Confidence in the verdict (0.0-1.0)", .range(0.0...1.0))
    public let confidence: Double

    @Guide(description: "Explanation of the verdict (evidence-based)")
    public let explanation: String

    @Guide(description: "Correct information (if incorrect or partiallyCorrect)")
    public let correction: String
}

// MARK: - Search Query Generation Response

/// Response from search query generation for fact verification.
@Generable
public struct VerificationSearchQueryResponse: Sendable {
    @Guide(description: "Search queries for verification (up to 3)")
    public let queries: [String]
}
