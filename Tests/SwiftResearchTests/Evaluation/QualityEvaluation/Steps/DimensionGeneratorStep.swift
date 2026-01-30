import Foundation
import SwiftAgent

// MARK: - Input

/// Input for dimension generation.
public struct DimensionGenerationInput: Sendable {
    /// The evaluation task.
    public let task: EvaluationTask

    /// Maximum number of task-specific dimensions to generate.
    public let maxDimensions: Int

    /// Creates a new dimension generation input.
    ///
    /// - Parameters:
    ///   - task: The evaluation task.
    ///   - maxDimensions: Maximum dimensions to generate.
    public init(task: EvaluationTask, maxDimensions: Int = 3) {
        self.task = task
        self.maxDimensions = maxDimensions
    }
}

// MARK: - DimensionGeneratorStep

/// A step that generates task-specific quality evaluation dimensions.
///
/// Analyzes the task requirements and generates dimensions that are
/// specifically relevant to evaluating the research output for this task.
///
/// ```swift
/// let step = DimensionGeneratorStep()
/// let dimensions = try await step
///     .session(session)
///     .run(DimensionGenerationInput(task: task, maxDimensions: 3))
/// ```
public struct DimensionGeneratorStep: Step, Sendable {
    public typealias Input = DimensionGenerationInput
    public typealias Output = [QualityDimension]

    @Session private var session: LanguageModelSession

    /// Creates a new dimension generator step.
    public init() {}

    public func run(_ input: DimensionGenerationInput) async throws -> [QualityDimension] {
        print("[DimensionGenerator] Building prompt...")
        let prompt = buildPrompt(for: input)
        print("[DimensionGenerator] Calling LLM for structured output...")

        do {
            let generateStep = Generate<String, DimensionGenerationResponse>(
                session: session,
                prompt: { Prompt($0) }
            )
            let response = try await generateStep.run(prompt)
            print("[DimensionGenerator] LLM response received, parsing dimensions...")

            // Convert generated dimensions to QualityDimension objects
            let taskSpecificDimensions = response.dimensions.prefix(input.maxDimensions).map { generated in
                QualityDimension(
                    name: generated.name,
                    dimensionDescription: generated.description,
                    weight: generated.importance,
                    isGeneral: false,
                    rubric: [
                        1: generated.rubricLow,
                        5: generated.rubricMid,
                        10: generated.rubricHigh
                    ]
                )
            }

            print("[DimensionGenerator] Successfully generated \(taskSpecificDimensions.count) dimensions")
            return Array(taskSpecificDimensions)
        } catch {
            // Fallback: Return empty array if structured output fails
            // This allows evaluation to continue with only general dimensions
            print("[DimensionGenerator] Warning: Failed to generate task-specific dimensions: \(error)")
            return []
        }
    }

    private func buildPrompt(for input: DimensionGenerationInput) -> String {
        let task = input.task
        return """
        Generate task-specific quality evaluation dimensions for the following research task.

        Task:
        - Objective: \(task.objective)
        - Domain: \(task.persona.domain.rawValue)
        - Requirements: \(task.requirements.joined(separator: "; "))
        - Expected format: \(task.expectedFormat.rawValue)
        - Difficulty: \(task.difficulty.rawValue)

        General dimensions (already included):
        - Coverage: Information completeness
        - Insight: Depth of analysis
        - Instruction-following: Adherence to requirements
        - Clarity: Communication quality

        Generate up to \(input.maxDimensions) ADDITIONAL task-specific dimensions that would be important
        for evaluating research output for THIS specific task.

        Examples of task-specific dimensions:
        - "Technical Accuracy" for technical tasks
        - "Source Diversity" for comparative analysis
        - "Practical Applicability" for how-to guides
        - "Temporal Coverage" for time-sensitive topics

        Do NOT repeat the general dimensions. Focus on what makes this task unique.

        IMPORTANT: Respond with a valid JSON object only. Do not include markdown formatting or code fences.
        """
    }
}
