import Foundation
import SwiftAgent

// MARK: - Input

/// Input for task generation.
public struct TaskGenerationInput: Sendable {
    /// The persona to generate tasks for.
    public let persona: Persona

    /// Number of tasks to generate.
    public let count: Int

    /// Creates a new task generation input.
    ///
    /// - Parameters:
    ///   - persona: The persona to generate tasks for.
    ///   - count: Number of tasks to generate.
    public init(persona: Persona, count: Int = 4) {
        self.persona = persona
        self.count = count
    }
}

// MARK: - TaskGeneratorStep

/// A step that generates research tasks based on a persona's characteristics.
///
/// Creates realistic research queries that the persona would naturally have,
/// with varying difficulty levels and output format requirements.
///
/// ```swift
/// let step = TaskGeneratorStep()
/// let tasks = try await step
///     .session(session)
///     .run(TaskGenerationInput(persona: persona, count: 4))
/// ```
public struct TaskGeneratorStep: Step, Sendable {
    public typealias Input = TaskGenerationInput
    public typealias Output = [EvaluationTask]

    @Session private var session: LanguageModelSession

    /// Creates a new task generator step.
    public init() {}

    public func run(_ input: TaskGenerationInput) async throws -> [EvaluationTask] {
        let prompt = buildPrompt(for: input)

        let generateStep = Generate<String, TaskGenerationResponse>(
            session: session,
            prompt: { Prompt($0) }
        )
        let response = try await generateStep.run(prompt)

        return response.tasks.map { generated in
            EvaluationTask(
                persona: input.persona,
                objective: generated.objective,
                requirements: generated.requirements,
                expectedFormat: generated.expectedFormat,
                difficulty: generated.difficulty,
                requiresRecentInfo: generated.requiresRecentInfo
            )
        }
    }

    private func buildPrompt(for input: TaskGenerationInput) -> String {
        let persona = input.persona
        return """
        Generate \(input.count) realistic research tasks for the following persona:

        Persona:
        - Role: \(persona.role)
        - Domain: \(persona.domain.rawValue)
        - Expertise: \(persona.expertise.rawValue)
        - Information needs: \(persona.informationNeeds.joined(separator: ", "))
        - Constraints: \(persona.constraints.joined(separator: ", "))

        Requirements for generated tasks:
        1. Tasks should be realistic queries this persona would naturally have
        2. Vary difficulty levels (easy, medium, hard)
        3. Include different output formats (report, summary, analysis, comparison, tutorial)
        4. Some tasks should require recent/current information, others can use historical data
        5. Each task should be specific enough to evaluate but complex enough to require deep research
        6. Tasks should NOT be answerable with simple factual recall

        Generate tasks that would genuinely benefit from web search and synthesis of multiple sources.
        """
    }
}

// MARK: - Batch Generation

extension TaskGeneratorStep {
    /// Generates tasks for multiple personas.
    ///
    /// - Parameters:
    ///   - personas: The personas to generate tasks for.
    ///   - tasksPerPersona: Number of tasks per persona.
    /// - Returns: All generated tasks.
    public func generateForPersonas(
        _ personas: [Persona],
        tasksPerPersona: Int = 4
    ) async throws -> [EvaluationTask] {
        var allTasks: [EvaluationTask] = []

        for persona in personas {
            let input = TaskGenerationInput(persona: persona, count: tasksPerPersona)
            let tasks = try await run(input)
            allTasks.append(contentsOf: tasks)
        }

        return allTasks
    }
}
