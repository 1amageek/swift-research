import Foundation
import SwiftAgent

// MARK: - Input

/// Input for feedback analysis.
public struct FeedbackAnalysisInput: Sendable {
    /// The evaluation result to analyze.
    public let evaluationResult: EvaluationResult

    /// History of previous evaluation results for comparison.
    public let history: [EvaluationResult]

    /// Creates a new feedback analysis input.
    ///
    /// - Parameters:
    ///   - evaluationResult: The evaluation result to analyze.
    ///   - history: Previous evaluation results.
    public init(evaluationResult: EvaluationResult, history: [EvaluationResult] = []) {
        self.evaluationResult = evaluationResult
        self.history = history
    }
}

/// Output from feedback analysis.
public struct FeedbackAnalysisOutput: Sendable {
    /// Improvement suggestions by phase.
    public let suggestions: FeedbackAnalysisResponse

    /// Diagnosed weaknesses.
    public let weaknesses: [DiagnosedWeakness]

    /// Priority actions to take.
    public let priorityActions: [ImprovementSuggestion]
}

// MARK: - FeedbackAnalyzerStep

/// A step that analyzes evaluation results to generate improvement suggestions.
///
/// Examines quality scores and fact-check results to identify weaknesses
/// and propose specific improvements for each SwiftResearch phase.
///
/// ```swift
/// let step = FeedbackAnalyzerStep()
/// let output = try await step
///     .session(session)
///     .run(FeedbackAnalysisInput(evaluationResult: result))
/// ```
public struct FeedbackAnalyzerStep: Step, Sendable {
    public typealias Input = FeedbackAnalysisInput
    public typealias Output = FeedbackAnalysisOutput

    @Session private var session: LanguageModelSession

    /// Creates a new feedback analyzer step.
    public init() {}

    public func run(_ input: FeedbackAnalysisInput) async throws -> FeedbackAnalysisOutput {
        // Diagnose weaknesses
        let weaknesses = try await diagnoseWeaknesses(input.evaluationResult)

        // Generate improvement suggestions
        let suggestions = try await generateSuggestions(
            evaluationResult: input.evaluationResult,
            weaknesses: weaknesses,
            history: input.history
        )

        // Prioritize actions
        let priorityActions = extractPriorityActions(from: suggestions)

        return FeedbackAnalysisOutput(
            suggestions: suggestions,
            weaknesses: weaknesses,
            priorityActions: priorityActions
        )
    }

    private func diagnoseWeaknesses(_ result: EvaluationResult) async throws -> [DiagnosedWeakness] {
        // Build error details with corrections
        let errorDetails = result.factCheckResult.errorSummary
        let errorContext: String
        if errorDetails.isEmpty {
            errorContext = "No factual errors with corrections recorded."
        } else {
            errorContext = errorDetails.prefix(5).enumerated().map { index, error in
                """
                  Error \(index + 1):
                    Statement: "\(error.statement.prefix(100))"
                    Correction: "\(error.correction.prefix(200))"
                """
            }.joined(separator: "\n")
        }

        // Include quality summary for context
        let qualitySummary = result.qualityResult.summary.isEmpty
            ? "No quality summary available."
            : result.qualityResult.summary

        let prompt = """
        Analyze the following evaluation result to diagnose weaknesses in the research system.

        Quality Evaluation:
        - Overall Score: \(String(format: "%.1f", result.qualityScore))/100
        - Summary: \(qualitySummary)
        - Dimension Scores:
        \(result.qualityResult.dimensionScores.map { "  - \($0.dimension.name): \($0.score)/10" }.joined(separator: "\n"))

        Fact Check Results:
        - Accuracy: \(String(format: "%.1f", result.factualAccuracy))%
        - Total Statements: \(result.factCheckResult.totalStatements)
        - Correct: \(result.factCheckResult.correctCount)
        - Incorrect: \(result.factCheckResult.incorrectCount)
        - Unknown: \(result.factCheckResult.unknownCount)

        Specific Errors and Corrections:
        \(errorContext)

        Identify the key weaknesses in this evaluation result.
        For each weakness:
        1. Categorize it (coverage, insight, accuracy, clarity, relevance)
        2. Describe the specific issue
        3. Identify the root cause
        4. Determine which SwiftResearch phase is affected (phase1, phase3, phase4, phase5)
        5. Rate the severity (0.0-1.0)

        Pay special attention to patterns in the factual errors - what types of claims are being incorrectly stated?
        Use the corrections to understand what kinds of facts the system is getting wrong.
        """

        let response = try await session.respond(generating: WeaknessDiagnosisResponse.self) {
            Prompt(prompt)
        }

        return response.content.weaknesses
    }

    private func generateSuggestions(
        evaluationResult: EvaluationResult,
        weaknesses: [DiagnosedWeakness],
        history: [EvaluationResult]
    ) async throws -> FeedbackAnalysisResponse {
        let historyContext = history.isEmpty ? "No previous evaluation history." : """
        Previous Evaluations:
        \(history.suffix(5).map { "- Overall: \(String(format: "%.1f", $0.overallScore)), Quality: \(String(format: "%.1f", $0.qualityScore)), Accuracy: \(String(format: "%.1f", $0.factualAccuracy))%" }.joined(separator: "\n"))
        """

        let weaknessContext = weaknesses.map { w in
            "- [\(w.category.rawValue)] \(w.weaknessDescription) (Phase: \(w.affectedPhase.rawValue), Severity: \(String(format: "%.2f", w.severity)))"
        }.joined(separator: "\n")

        // Include quality insights from the evaluation
        let qualityInsights: String
        if !evaluationResult.qualityResult.weaknesses.isEmpty {
            qualityInsights = """
            Quality Weaknesses Identified:
            \(evaluationResult.qualityResult.weaknesses.map { "- \($0)" }.joined(separator: "\n"))

            Suggested Improvements from Quality Evaluation:
            \(evaluationResult.qualityResult.improvements.map { "- \($0)" }.joined(separator: "\n"))
            """
        } else {
            qualityInsights = "No specific quality weaknesses identified."
        }

        // Include specific factual errors for Phase 5 improvements
        let factualErrorContext: String
        let errors = evaluationResult.factCheckResult.errorSummary
        if errors.isEmpty {
            factualErrorContext = "No specific factual errors recorded."
        } else {
            factualErrorContext = """
            Factual Errors to Address in Phase 5:
            \(errors.prefix(3).map { "- Wrong: \"\($0.statement.prefix(80))...\" → Correct: \"\($0.correction.prefix(100))...\"" }.joined(separator: "\n"))
            """
        }

        let prompt = """
        Based on the following evaluation results and diagnosed weaknesses, generate specific improvement suggestions
        for each phase of the SwiftResearch pipeline.

        Current Evaluation:
        - Overall Score: \(String(format: "%.1f", evaluationResult.overallScore))/100
        - Quality Score: \(String(format: "%.1f", evaluationResult.qualityScore))/100
        - Factual Accuracy: \(String(format: "%.1f", evaluationResult.factualAccuracy))%

        \(historyContext)

        Diagnosed Weaknesses:
        \(weaknessContext)

        \(qualityInsights)

        \(factualErrorContext)

        Generate improvement suggestions for each phase:
        - Phase 1 (Objective Analysis): Keywords, questions, success criteria generation
        - Phase 3 (Content Review): Information extraction, relevance assessment
        - Phase 4 (Sufficiency Check): Determining when enough information is collected
        - Phase 5 (Response Building): Final report generation - USE THE FACTUAL ERRORS ABOVE to suggest how to improve fact accuracy

        For each suggestion, specify:
        1. The target parameter or prompt element
        2. The current issue
        3. The suggested change
        4. Expected impact (0.0-1.0)
        5. Priority (high/medium/low)
        """

        let response = try await session.respond(generating: FeedbackAnalysisResponse.self) {
            Prompt(prompt)
        }
        return response.content
    }

    private func extractPriorityActions(from suggestions: FeedbackAnalysisResponse) -> [ImprovementSuggestion] {
        let allSuggestions = suggestions.phase1Improvements
            + suggestions.phase3Improvements
            + suggestions.phase4Improvements
            + suggestions.phase5Improvements

        // Sort by priority and impact
        return allSuggestions
            .sorted { lhs, rhs in
                let lhsPriority = priorityValue(lhs.priority)
                let rhsPriority = priorityValue(rhs.priority)

                if lhsPriority != rhsPriority {
                    return lhsPriority > rhsPriority
                }
                return lhs.expectedImpact > rhs.expectedImpact
            }
            .prefix(5)
            .map { $0 }
    }

    private func priorityValue(_ priority: ImprovementPriority) -> Int {
        switch priority {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }
}
