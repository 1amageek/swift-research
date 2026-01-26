import Foundation
import Testing
@testable import SwiftResearch

/// Tests for Evaluation data models to verify the feedback loop data flow.
@Suite("Evaluation Model Tests")
struct EvaluationModelTests {

    // MARK: - FactVerificationResult Tests

    @Test("FactVerificationResult includes correction field")
    func factVerificationResultWithCorrection() {
        let statement = VerifiableStatement(
            text: "The population of Tokyo is 50 million",
            type: .numeric,
            sourceSection: "Demographics",
            verifiabilityConfidence: 0.9,
            suggestedSearchQuery: "Tokyo population 2024"
        )

        let result = FactVerificationResult(
            statement: statement,
            verdict: .incorrect,
            evidence: [],
            confidence: 0.85,
            explanation: "The population of Tokyo is approximately 14 million, not 50 million.",
            correction: "The population of Tokyo metropolitan area is approximately 14 million as of 2024."
        )

        #expect(result.correction != nil)
        #expect(result.correction!.contains("14 million"))
        #expect(result.verdict == .incorrect)
    }

    @Test("FactVerificationResult without correction for correct verdict")
    func factVerificationResultWithoutCorrection() {
        let statement = VerifiableStatement(
            text: "Swift was released in 2014",
            type: .temporal,
            sourceSection: "History",
            verifiabilityConfidence: 0.95,
            suggestedSearchQuery: nil
        )

        let result = FactVerificationResult(
            statement: statement,
            verdict: .correct,
            evidence: [],
            confidence: 0.9,
            explanation: "Swift was indeed released at WWDC 2014.",
            correction: nil
        )

        #expect(result.correction == nil)
        #expect(result.verdict == .correct)
    }

    @Test("FactCheckResult errorSummary returns corrections")
    func factCheckResultErrorSummary() {
        let statement1 = VerifiableStatement(
            text: "Python was created in 1985",
            type: .temporal,
            sourceSection: "History",
            verifiabilityConfidence: 0.9,
            suggestedSearchQuery: nil
        )

        let statement2 = VerifiableStatement(
            text: "JavaScript runs on the server",
            type: .entity,
            sourceSection: "Technical",
            verifiabilityConfidence: 0.8,
            suggestedSearchQuery: nil
        )

        let verification1 = FactVerificationResult(
            statement: statement1,
            verdict: .incorrect,
            evidence: [],
            confidence: 0.9,
            explanation: "Python was created in 1991, not 1985.",
            correction: "Python was created by Guido van Rossum in 1991."
        )

        let verification2 = FactVerificationResult(
            statement: statement2,
            verdict: .correct,
            evidence: [],
            confidence: 0.85,
            explanation: "JavaScript can run on servers with Node.js.",
            correction: nil
        )

        let factCheckResult = FactCheckResult(verifications: [verification1, verification2])

        #expect(factCheckResult.totalStatements == 2)
        #expect(factCheckResult.incorrectCount == 1)
        #expect(factCheckResult.correctCount == 1)

        let errorSummary = factCheckResult.errorSummary
        #expect(errorSummary.count == 1)
        #expect(errorSummary[0].statement.contains("Python"))
        #expect(errorSummary[0].correction.contains("1991"))
    }

    @Test("FactCheckResult verificationsWithCorrections")
    func factCheckResultVerificationsWithCorrections() {
        let statement1 = VerifiableStatement(
            text: "Statement 1",
            type: .entity,
            sourceSection: "Test",
            verifiabilityConfidence: 0.9,
            suggestedSearchQuery: nil
        )

        let statement2 = VerifiableStatement(
            text: "Statement 2",
            type: .entity,
            sourceSection: "Test",
            verifiabilityConfidence: 0.9,
            suggestedSearchQuery: nil
        )

        let verification1 = FactVerificationResult(
            statement: statement1,
            verdict: .partiallyCorrect,
            evidence: [],
            confidence: 0.7,
            explanation: "Partially correct.",
            correction: "More accurate version of statement 1."
        )

        let verification2 = FactVerificationResult(
            statement: statement2,
            verdict: .unknown,
            evidence: [],
            confidence: 0.3,
            explanation: "Unable to verify.",
            correction: nil
        )

        let factCheckResult = FactCheckResult(verifications: [verification1, verification2])

        let withCorrections = factCheckResult.verificationsWithCorrections
        #expect(withCorrections.count == 1)
        #expect(withCorrections[0].verdict == .partiallyCorrect)
    }

    // MARK: - QualityEvaluationResult Tests

    @Test("QualityEvaluationResult includes summary field")
    func qualityEvaluationResultWithSummary() {
        let dimension = QualityDimension(
            name: "Coverage",
            dimensionDescription: "Information completeness",
            weight: 0.25,
            isGeneral: true,
            rubric: [1: "Poor", 5: "Average", 10: "Excellent"]
        )

        let score = DimensionScore(
            dimension: dimension,
            score: 8,
            reasoning: "Good coverage of the topic.",
            evidence: ["Covered all major points"],
            suggestions: ["Could add more details on X"]
        )

        let result = QualityEvaluationResult(
            dimensionScores: [score],
            summary: "Overall, the research output demonstrates strong coverage with minor areas for improvement.",
            strengths: ["Comprehensive coverage", "Clear structure"],
            weaknesses: ["Limited depth on technical details"],
            improvements: ["Add more technical analysis"]
        )

        #expect(!result.summary.isEmpty)
        #expect(result.summary.contains("strong coverage"))
        #expect(result.strengths.count == 2)
        #expect(result.weaknesses.count == 1)
        #expect(result.improvements.count == 1)
    }

    @Test("QualityEvaluationResult calculates weighted score correctly")
    func qualityEvaluationResultWeightedScore() {
        let dim1 = QualityDimension(
            name: "Dimension 1",
            dimensionDescription: "Test",
            weight: 0.6,
            isGeneral: true,
            rubric: [:]
        )

        let dim2 = QualityDimension(
            name: "Dimension 2",
            dimensionDescription: "Test",
            weight: 0.4,
            isGeneral: true,
            rubric: [:]
        )

        let score1 = DimensionScore(
            dimension: dim1,
            score: 8,
            reasoning: "Good",
            evidence: [],
            suggestions: []
        )

        let score2 = DimensionScore(
            dimension: dim2,
            score: 6,
            reasoning: "OK",
            evidence: [],
            suggestions: []
        )

        let result = QualityEvaluationResult(
            dimensionScores: [score1, score2],
            summary: "Test summary"
        )

        // Weighted average: (8 * 0.6 + 6 * 0.4) / (0.6 + 0.4) = (4.8 + 2.4) / 1.0 = 7.2
        #expect(abs(result.weightedAverageScore - 7.2) < 0.01)
        #expect(abs(result.normalizedScore - 72.0) < 0.1)
    }

    // MARK: - DimensionScore Tests

    @Test("DimensionScore includes suggestions field")
    func dimensionScoreWithSuggestions() {
        let dimension = QualityDimension(
            name: "Insight",
            dimensionDescription: "Depth of analysis",
            weight: 0.25,
            isGeneral: true,
            rubric: [:]
        )

        let score = DimensionScore(
            dimension: dimension,
            score: 7,
            reasoning: "Shows good analytical depth.",
            evidence: ["Analysis of market trends", "Comparison with competitors"],
            suggestions: ["Add quantitative analysis", "Include more data sources"]
        )

        #expect(score.suggestions.count == 2)
        #expect(score.suggestions[0].contains("quantitative"))
        #expect(score.score == 7)
    }

    // MARK: - VerifiableStatement Tests

    @Test("VerifiableStatement includes suggestedSearchQuery")
    func verifiableStatementWithSearchQuery() {
        let statement = VerifiableStatement(
            text: "Apple acquired OpenAI in 2024",
            type: .entity,
            sourceSection: "Business News",
            verifiabilityConfidence: 0.95,
            suggestedSearchQuery: "Apple OpenAI acquisition 2024"
        )

        #expect(statement.suggestedSearchQuery != nil)
        #expect(statement.suggestedSearchQuery!.contains("Apple"))
        #expect(statement.suggestedSearchQuery!.contains("OpenAI"))
    }

    @Test("VerifiableStatement without suggestedSearchQuery")
    func verifiableStatementWithoutSearchQuery() {
        let statement = VerifiableStatement(
            text: "Water boils at 100 degrees Celsius",
            type: .numeric,
            sourceSection: "Science",
            verifiabilityConfidence: 0.99,
            suggestedSearchQuery: nil
        )

        #expect(statement.suggestedSearchQuery == nil)
    }
}
