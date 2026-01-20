import Foundation
import SwiftAgent

// MARK: - Input

/// Input for adaptive quality evaluation.
public struct QualityEvaluationInput: Sendable {
    /// The evaluation task.
    public let task: EvaluationTask

    /// The research output to evaluate.
    public let researchOutput: String

    /// Weight for general dimensions (0.0-1.0).
    public let generalWeight: Double

    /// Maximum task-specific dimensions to generate.
    public let maxTaskSpecificDimensions: Int

    /// Creates a new quality evaluation input.
    ///
    /// - Parameters:
    ///   - task: The evaluation task.
    ///   - researchOutput: The research output markdown.
    ///   - generalWeight: Weight for general dimensions.
    ///   - maxTaskSpecificDimensions: Maximum task-specific dimensions.
    public init(
        task: EvaluationTask,
        researchOutput: String,
        generalWeight: Double = 0.6,
        maxTaskSpecificDimensions: Int = 3
    ) {
        self.task = task
        self.researchOutput = researchOutput
        self.generalWeight = generalWeight
        self.maxTaskSpecificDimensions = maxTaskSpecificDimensions
    }
}

// MARK: - AdaptiveQualityStep

/// A step that performs adaptive quality evaluation combining general and task-specific dimensions.
///
/// This step:
/// 1. Uses general quality dimensions (Coverage, Insight, Instruction-following, Clarity)
/// 2. Generates task-specific dimensions based on the task requirements
/// 3. Scores the research output on all dimensions in parallel
/// 4. Computes weighted aggregate scores
///
/// ```swift
/// let step = AdaptiveQualityStep()
/// let result = try await step
///     .session(session)
///     .run(QualityEvaluationInput(task: task, researchOutput: markdown))
/// ```
public struct AdaptiveQualityStep: Step, Sendable {
    public typealias Input = QualityEvaluationInput
    public typealias Output = QualityEvaluationResult

    @Session private var session: LanguageModelSession

    /// Creates a new adaptive quality step.
    public init() {}

    public func run(_ input: QualityEvaluationInput) async throws -> QualityEvaluationResult {
        print("[AdaptiveQuality] Starting evaluation...")

        // Step 1: Generate task-specific dimensions
        print("[AdaptiveQuality] Step 1: Generating task-specific dimensions...")
        let dimensionGenerator = DimensionGeneratorStep()
            .session(session)

        let taskSpecificDimensions = try await dimensionGenerator.run(
            DimensionGenerationInput(
                task: input.task,
                maxDimensions: input.maxTaskSpecificDimensions
            )
        )
        print("[AdaptiveQuality] Step 1 complete: Generated \(taskSpecificDimensions.count) task-specific dimensions")

        // Step 2: Combine general and task-specific dimensions
        print("[AdaptiveQuality] Step 2: Combining dimensions...")
        let generalDimensions = QualityDimension.generalDimensions

        // Normalize weights
        let totalGeneralWeight = generalDimensions.reduce(0) { $0 + $1.weight }
        let totalTaskSpecificWeight = taskSpecificDimensions.reduce(0) { $0 + $1.weight }

        var normalizedDimensions: [QualityDimension] = []

        // Adjust general dimension weights
        for dim in generalDimensions {
            let normalizedWeight = totalGeneralWeight > 0
                ? (dim.weight / totalGeneralWeight) * input.generalWeight
                : input.generalWeight / Double(generalDimensions.count)
            normalizedDimensions.append(dim.withWeight(normalizedWeight))
        }

        // Adjust task-specific dimension weights
        let taskSpecificWeight = 1.0 - input.generalWeight
        for dim in taskSpecificDimensions {
            let normalizedWeight = totalTaskSpecificWeight > 0
                ? (dim.weight / totalTaskSpecificWeight) * taskSpecificWeight
                : taskSpecificWeight / Double(taskSpecificDimensions.count)
            normalizedDimensions.append(dim.withWeight(normalizedWeight))
        }
        print("[AdaptiveQuality] Step 2 complete: \(normalizedDimensions.count) total dimensions")

        // Step 3: Score all dimensions sequentially
        print("[AdaptiveQuality] Step 3: Scoring dimensions...")
        var scores: [DimensionScore] = []
        for (index, dimension) in normalizedDimensions.enumerated() {
            print("[AdaptiveQuality]   Scoring dimension \(index + 1)/\(normalizedDimensions.count): \(dimension.name)")
            let scorer = DimensionScorerStep()
                .session(session)
            let scoringInput = DimensionScoringInput(
                task: input.task,
                researchOutput: input.researchOutput,
                dimension: dimension
            )
            let score = try await scorer.run(scoringInput)
            scores.append(score)
            print("[AdaptiveQuality]   Dimension '\(dimension.name)' scored: \(score.score)/10")
        }
        print("[AdaptiveQuality] Step 3 complete: All dimensions scored")

        // Step 4: Generate overall assessment (strengths, weaknesses, improvements)
        print("[AdaptiveQuality] Step 4: Generating overall assessment...")
        let summary: String
        let strengths: [String]
        let weaknesses: [String]
        let improvements: [String]

        do {
            let overallAssessment = try await generateOverallAssessment(
                task: input.task,
                researchOutput: input.researchOutput,
                dimensionScores: scores
            )
            summary = overallAssessment.summary
            strengths = overallAssessment.strengths
            weaknesses = overallAssessment.weaknesses
            improvements = overallAssessment.priorityImprovements
            print("[AdaptiveQuality] Step 4 complete: Overall assessment generated via LLM")
        } catch {
            print("[AdaptiveQuality] Warning: Overall assessment failed, using fallback: \(error)")
            let fallback = generateFallbackAssessment(dimensionScores: scores)
            summary = fallback.summary
            strengths = fallback.strengths
            weaknesses = fallback.weaknesses
            improvements = fallback.improvements
            print("[AdaptiveQuality] Step 4 complete: Used fallback assessment")
        }

        // Step 5: Compute aggregate scores with overall assessment
        print("[AdaptiveQuality] Step 5: Building result...")
        let result = QualityEvaluationResult(
            dimensionScores: scores,
            summary: summary,
            strengths: strengths,
            weaknesses: weaknesses,
            improvements: improvements
        )
        print("[AdaptiveQuality] Evaluation complete!")
        return result
    }

    private func generateOverallAssessment(
        task: EvaluationTask,
        researchOutput: String,
        dimensionScores: [DimensionScore]
    ) async throws -> OverallQualityResponse {
        let scoresDescription = dimensionScores.map { score in
            """
            - \(score.dimension.name): \(score.score)/10
              Reasoning: \(score.reasoning)
              Suggestions: \(score.suggestions.joined(separator: "; "))
            """
        }.joined(separator: "\n")

        let prompt = """
        Based on the following dimension-by-dimension quality evaluation, provide an overall assessment.

        Task:
        - Objective: \(task.objective)
        - Requirements: \(task.requirements.joined(separator: "; "))

        Dimension Scores:
        \(scoresDescription)

        Research Output (excerpt):
        ---
        \(String(researchOutput.prefix(3000)))
        ---

        Synthesize the dimension evaluations into:
        1. Key strengths (2-3 most notable positive aspects)
        2. Key weaknesses (2-3 areas needing improvement)
        3. Priority improvements (2-3 actionable suggestions ranked by impact)

        Focus on patterns across dimensions rather than repeating individual dimension feedback.
        """

        let response = try await session.respond(generating: OverallQualityResponse.self) {
            Prompt(prompt)
        }

        return response.content
    }

    /// Generates a fallback assessment when LLM structured output fails.
    private func generateFallbackAssessment(
        dimensionScores: [DimensionScore]
    ) -> (summary: String, strengths: [String], weaknesses: [String], improvements: [String]) {
        // Extract summary from dimension scores
        let avgScore = dimensionScores.isEmpty ? 5.0 : Double(dimensionScores.reduce(0) { $0 + $1.score }) / Double(dimensionScores.count)
        let summary = "Overall quality score: \(String(format: "%.1f", avgScore))/10 based on \(dimensionScores.count) dimensions."

        // Extract strengths from high-scoring dimensions
        let strengths: [String] = dimensionScores
            .filter { $0.score >= 7 }
            .prefix(3)
            .map { "\($0.dimension.name) scored \($0.score)/10" }

        // Extract weaknesses from low-scoring dimensions
        let weaknesses: [String] = dimensionScores
            .filter { $0.score <= 5 }
            .prefix(3)
            .map { "\($0.dimension.name) scored \($0.score)/10" }

        // Extract suggestions
        let improvements: [String] = dimensionScores
            .flatMap { $0.suggestions }
            .prefix(3)
            .map { $0 }

        return (summary, Array(strengths), Array(weaknesses), Array(improvements))
    }
}

// MARK: - QualityDimension Weight Helper

extension QualityDimension {
    /// Creates a copy with a new weight.
    func withWeight(_ newWeight: Double) -> QualityDimension {
        QualityDimension(
            id: self.id,
            name: self.name,
            dimensionDescription: self.dimensionDescription,
            weight: newWeight,
            isGeneral: self.isGeneral,
            rubric: self.rubric
        )
    }
}
