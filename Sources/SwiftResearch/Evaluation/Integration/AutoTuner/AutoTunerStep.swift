import Foundation
import SwiftAgent

// MARK: - Input

/// Input for auto-tuning.
public struct AutoTunerInput: Sendable {
    /// Feedback analysis output.
    public let feedback: FeedbackAnalysisOutput

    /// Current prompt templates.
    public let templates: [PromptTemplate]

    /// Evaluation task for A/B testing.
    public let testTask: EvaluationTask?

    /// Research result for A/B testing.
    public let testResearchResult: AggregatedResult?

    /// Creates a new auto-tuner input.
    ///
    /// - Parameters:
    ///   - feedback: Feedback analysis output.
    ///   - templates: Current prompt templates.
    ///   - testTask: Optional test task for A/B testing.
    ///   - testResearchResult: Optional test research result.
    public init(
        feedback: FeedbackAnalysisOutput,
        templates: [PromptTemplate],
        testTask: EvaluationTask? = nil,
        testResearchResult: AggregatedResult? = nil
    ) {
        self.feedback = feedback
        self.templates = templates
        self.testTask = testTask
        self.testResearchResult = testResearchResult
    }
}

/// Output from auto-tuning.
public struct AutoTunerOutput: Sendable {
    /// Updated prompt templates.
    public let updatedTemplates: [PromptTemplate]

    /// Parameter adjustments made.
    public let adjustments: [ParameterAdjustment]

    /// A/B test results (if tests were run).
    public let abTestResults: [ABTestResult]

    /// Tuning result status.
    public let result: TuningResult
}

// MARK: - AutoTunerStep

/// A step that automatically tunes prompt parameters based on feedback.
///
/// Analyzes improvement suggestions and adjusts prompt template parameters
/// to improve research quality. Optionally runs A/B tests to validate improvements.
///
/// ```swift
/// let step = AutoTunerStep()
/// let output = try await step
///     .session(session)
///     .run(AutoTunerInput(feedback: feedback, templates: templates))
/// ```
public struct AutoTunerStep: Step, Sendable {
    public typealias Input = AutoTunerInput
    public typealias Output = AutoTunerOutput

    @Session private var session: LanguageModelSession

    /// Minimum improvement threshold to accept changes.
    public let minImprovementThreshold: Double

    /// Maximum degradation threshold before rollback.
    public let maxDegradationThreshold: Double

    /// Creates a new auto-tuner step.
    ///
    /// - Parameters:
    ///   - minImprovementThreshold: Minimum improvement to accept.
    ///   - maxDegradationThreshold: Maximum degradation before rollback.
    public init(
        minImprovementThreshold: Double = 0.01,
        maxDegradationThreshold: Double = 0.05
    ) {
        self.minImprovementThreshold = minImprovementThreshold
        self.maxDegradationThreshold = maxDegradationThreshold
    }

    public func run(_ input: AutoTunerInput) async throws -> AutoTunerOutput {
        // Generate parameter adjustments based on feedback
        let adjustments = try await generateAdjustments(
            feedback: input.feedback,
            templates: input.templates
        )

        // Apply adjustments to templates
        var updatedTemplates = input.templates
        for adjustment in adjustments {
            updatedTemplates = applyAdjustment(adjustment, to: updatedTemplates)
        }

        // Run A/B tests if test data is available
        var abTestResults: [ABTestResult] = []
        if let testTask = input.testTask, let testResult = input.testResearchResult {
            abTestResults = try await runABTests(
                adjustments: adjustments,
                originalTemplates: input.templates,
                updatedTemplates: updatedTemplates,
                testTask: testTask,
                testResearchResult: testResult
            )
        }

        // Determine tuning result
        let result = determineTuningResult(
            adjustments: adjustments,
            abTestResults: abTestResults
        )

        // If rollback needed, revert to original templates
        let finalTemplates: [PromptTemplate]
        switch result {
        case .rollback:
            finalTemplates = input.templates
        default:
            finalTemplates = updatedTemplates
        }

        return AutoTunerOutput(
            updatedTemplates: finalTemplates,
            adjustments: adjustments,
            abTestResults: abTestResults,
            result: result
        )
    }

    // MARK: - Adjustment Generation

    private func generateAdjustments(
        feedback: FeedbackAnalysisOutput,
        templates: [PromptTemplate]
    ) async throws -> [ParameterAdjustment] {
        let priorityActions = feedback.priorityActions

        guard !priorityActions.isEmpty else {
            return []
        }

        // Map suggestions to parameters
        let suggestionContext = priorityActions.map { suggestion in
            """
            Target: \(suggestion.target)
            Issue: \(suggestion.currentIssue)
            Suggested Change: \(suggestion.suggestedChange)
            Expected Impact: \(String(format: "%.2f", suggestion.expectedImpact))
            """
        }.joined(separator: "\n\n")

        let templateContext = templates.map { template in
            """
            Phase: \(template.phase.rawValue)
            Parameters:
            \(template.parameters.map { "  - \($0.name): \($0.description) (current: \(template.currentValues[$0.name] ?? $0.defaultValue))" }.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n")

        let prompt = """
        Based on the following improvement suggestions and available parameters,
        generate specific parameter adjustments.

        Improvement Suggestions:
        \(suggestionContext)

        Available Parameters:
        \(templateContext)

        For each suggestion, determine which parameter should be adjusted and what the new value should be.
        Only suggest adjustments for parameters that exist.
        """

        let response = try await session.respond(generating: ParameterAdjustmentResponse.self) {
            Prompt(prompt)
        }

        return response.content.adjustments
    }

    // MARK: - Apply Adjustments

    private func applyAdjustment(
        _ adjustment: ParameterAdjustment,
        to templates: [PromptTemplate]
    ) -> [PromptTemplate] {
        templates.map { template in
            if template.currentValues.keys.contains(adjustment.parameterName) {
                return template.with(adjustment.parameterName, value: adjustment.suggestedValue)
            }
            return template
        }
    }

    // MARK: - A/B Testing

    private func runABTests(
        adjustments: [ParameterAdjustment],
        originalTemplates: [PromptTemplate],
        updatedTemplates: [PromptTemplate],
        testTask: EvaluationTask,
        testResearchResult: AggregatedResult
    ) async throws -> [ABTestResult] {
        // For now, return empty array - full A/B testing would require
        // running the research pipeline with different parameters
        // This is a placeholder for the full implementation
        return []
    }

    // MARK: - Result Determination

    private func determineTuningResult(
        adjustments: [ParameterAdjustment],
        abTestResults: [ABTestResult]
    ) -> TuningResult {
        if adjustments.isEmpty {
            return .noChange(reason: "No adjustments were generated")
        }

        // Check A/B test results if available
        if let mainResult = abTestResults.first {
            if mainResult.shouldAccept {
                return .improved(mainResult)
            } else if mainResult.improvementPercentage < -maxDegradationThreshold {
                return .rollback(previousVersion: 0, reason: "Significant degradation detected")
            }
        }

        // If no A/B tests, return improved based on adjustments
        return .noChange(reason: "Changes applied, awaiting validation")
    }
}
