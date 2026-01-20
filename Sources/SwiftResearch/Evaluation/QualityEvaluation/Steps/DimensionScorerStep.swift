import Foundation
import SwiftAgent

// MARK: - Input

/// Input for dimension scoring.
public struct DimensionScoringInput: Sendable {
    /// The evaluation task.
    public let task: EvaluationTask

    /// The research output to evaluate.
    public let researchOutput: String

    /// The dimension to score.
    public let dimension: QualityDimension

    /// Creates a new dimension scoring input.
    ///
    /// - Parameters:
    ///   - task: The evaluation task.
    ///   - researchOutput: The research output markdown.
    ///   - dimension: The dimension to score.
    public init(task: EvaluationTask, researchOutput: String, dimension: QualityDimension) {
        self.task = task
        self.researchOutput = researchOutput
        self.dimension = dimension
    }
}

// MARK: - DimensionScorerStep

/// A step that scores research output on a specific quality dimension.
///
/// Evaluates the research output against the dimension's rubric and
/// provides detailed reasoning and evidence for the score.
///
/// ```swift
/// let step = DimensionScorerStep()
/// let score = try await step
///     .session(session)
///     .run(DimensionScoringInput(task: task, researchOutput: markdown, dimension: dimension))
/// ```
public struct DimensionScorerStep: Step, Sendable {
    public typealias Input = DimensionScoringInput
    public typealias Output = DimensionScore

    @Session private var session: LanguageModelSession

    /// Creates a new dimension scorer step.
    public init() {}

    public func run(_ input: DimensionScoringInput) async throws -> DimensionScore {
        print("[DimensionScorer] Building prompt for '\(input.dimension.name)'...")
        let prompt = buildPrompt(for: input)
        print("[DimensionScorer] Calling LLM for scoring...")

        do {
            let response = try await session.respond(generating: DimensionScoreResponse.self) {
                Prompt(prompt)
            }
            print("[DimensionScorer] LLM response received for '\(input.dimension.name)'")

            return DimensionScore(
                dimension: input.dimension,
                score: response.content.score,
                reasoning: response.content.reasoning,
                evidence: response.content.evidence,
                suggestions: response.content.suggestions
            )
        } catch {
            // Fallback: Return a default score if structured output fails
            print("[DimensionScorer] Warning: Failed to score \(input.dimension.name): \(error)")
            return DimensionScore(
                dimension: input.dimension,
                score: 5,  // Default to middle score
                reasoning: "Scoring failed due to LLM response parsing error.",
                evidence: [],
                suggestions: []
            )
        }
    }

    private func buildPrompt(for input: DimensionScoringInput) -> String {
        let rubricDescription = input.dimension.rubric
            .sorted { $0.key < $1.key }
            .map { "  Score \($0.key): \($0.value)" }
            .joined(separator: "\n")

        return """
        Evaluate the following research output on the "\(input.dimension.name)" dimension.

        Task:
        - Objective: \(input.task.objective)
        - Requirements: \(input.task.requirements.joined(separator: "; "))

        Dimension: \(input.dimension.name)
        Description: \(input.dimension.dimensionDescription)

        Rubric:
        \(rubricDescription)

        Research Output:
        ---
        \(input.researchOutput.prefix(8000))
        ---

        Carefully evaluate the research output against the rubric.
        Provide:
        1. A score from 1-10
        2. Detailed reasoning for the score
        3. Specific evidence (quotes or references) from the output
        4. Suggestions for improvement
        """
    }
}

// MARK: - Parallel Scoring

extension DimensionScorerStep {
    /// Scores multiple dimensions sequentially.
    ///
    /// - Parameters:
    ///   - task: The evaluation task.
    ///   - researchOutput: The research output to evaluate.
    ///   - dimensions: Dimensions to score.
    /// - Returns: Array of dimension scores.
    public func scoreAll(
        task: EvaluationTask,
        researchOutput: String,
        dimensions: [QualityDimension]
    ) async throws -> [DimensionScore] {
        var scores: [DimensionScore] = []
        for dimension in dimensions {
            let input = DimensionScoringInput(
                task: task,
                researchOutput: researchOutput,
                dimension: dimension
            )
            let score = try await run(input)
            scores.append(score)
        }
        return scores
    }
}
