import Foundation
import SwiftAgent

// MARK: - Input

/// Input for task filtering.
public struct TaskFilterInput: Sendable {
    /// Tasks to filter.
    public let tasks: [EvaluationTask]

    /// Minimum search necessity score to qualify.
    public let qualificationThreshold: Double

    /// Creates a new task filter input.
    ///
    /// - Parameters:
    ///   - tasks: Tasks to filter.
    ///   - qualificationThreshold: Minimum score to qualify (0.0-1.0).
    public init(tasks: [EvaluationTask], qualificationThreshold: Double = 0.7) {
        self.tasks = tasks
        self.qualificationThreshold = qualificationThreshold
    }
}

/// Output from task filtering.
public struct TaskFilterOutput: Sendable {
    /// Tasks that passed all filters.
    public let qualifiedTasks: [EvaluationTask]

    /// Tasks that failed filtering with reasons.
    public let disqualifiedTasks: [(task: EvaluationTask, reason: String)]

    /// Statistics about the filtering process.
    public let statistics: FilterStatistics
}

/// Statistics from the filtering process.
public struct FilterStatistics: Sendable {
    /// Total tasks processed.
    public let totalTasks: Int

    /// Tasks that passed Stage 1 (Task Qualification).
    public let passedStage1: Int

    /// Tasks that passed Stage 2 (Search Necessity).
    public let passedStage2: Int

    /// Final qualified count.
    public let qualifiedCount: Int

    /// Qualification rate.
    public var qualificationRate: Double {
        totalTasks > 0 ? Double(qualifiedCount) / Double(totalTasks) : 0
    }
}

// MARK: - TaskFilterStep

/// A step that filters evaluation tasks through a two-stage qualification process.
///
/// Stage 1: Task Qualification - Determines if the task requires recent information.
/// Stage 2: Search Necessity - Determines if web search is necessary (can't be answered by LLM alone).
///
/// ```swift
/// let step = TaskFilterStep()
/// let output = try await step
///     .session(session)
///     .run(TaskFilterInput(tasks: tasks, qualificationThreshold: 0.7))
/// ```
public struct TaskFilterStep: Step, Sendable {
    public typealias Input = TaskFilterInput
    public typealias Output = TaskFilterOutput

    @Session private var session: LanguageModelSession

    /// Creates a new task filter step.
    public init() {}

    public func run(_ input: TaskFilterInput) async throws -> TaskFilterOutput {
        var qualifiedTasks: [EvaluationTask] = []
        var disqualifiedTasks: [(task: EvaluationTask, reason: String)] = []
        var passedStage1 = 0
        var passedStage2 = 0

        for var task in input.tasks {
            // Stage 1: Task Qualification
            let stage1Result = try await runStage1Qualification(task)

            if !stage1Result.requiresRecentInfo && stage1Result.recencyImportance < 0.3 {
                task.qualificationStatus = .disqualified
                task.disqualificationReason = "Does not require recent information: \(stage1Result.reasoning)"
                disqualifiedTasks.append((task, "Stage 1: \(stage1Result.reasoning)"))
                continue
            }

            passedStage1 += 1
            task.requiresRecentInfo = stage1Result.requiresRecentInfo

            // Stage 2: Search Necessity
            let stage2Result = try await runStage2SearchNecessity(task)

            if stage2Result.necessityScore < input.qualificationThreshold {
                task.qualificationStatus = .disqualified
                task.disqualificationReason = "Search not necessary: \(stage2Result.reasoning)"
                disqualifiedTasks.append((task, "Stage 2: \(stage2Result.reasoning)"))
                continue
            }

            passedStage2 += 1
            task.searchNecessityScore = stage2Result.necessityScore
            task.qualificationStatus = .qualified
            qualifiedTasks.append(task)
        }

        let statistics = FilterStatistics(
            totalTasks: input.tasks.count,
            passedStage1: passedStage1,
            passedStage2: passedStage2,
            qualifiedCount: qualifiedTasks.count
        )

        return TaskFilterOutput(
            qualifiedTasks: qualifiedTasks,
            disqualifiedTasks: disqualifiedTasks,
            statistics: statistics
        )
    }

    // MARK: - Stage 1: Task Qualification

    private func runStage1Qualification(_ task: EvaluationTask) async throws -> TaskQualificationResponse {
        let prompt = """
        Evaluate whether the following research task requires recent/current information to be answered properly.

        Task:
        - Objective: \(task.objective)
        - Domain: \(task.persona.domain.rawValue)
        - Requirements: \(task.requirements.joined(separator: "; "))

        Consider:
        1. Does this task involve rapidly changing information (e.g., current events, recent developments)?
        2. Would outdated information significantly reduce the quality of the answer?
        3. Is there a temporal component that makes recency important?

        Evaluate and provide your assessment.
        """

        let response = try await session.respond(generating: TaskQualificationResponse.self) {
            Prompt(prompt)
        }
        return response.content
    }

    // MARK: - Stage 2: Search Necessity

    private func runStage2SearchNecessity(_ task: EvaluationTask) async throws -> SearchNecessityResponse {
        let prompt = """
        Evaluate whether the following research task requires web search to be answered properly,
        or if it can be adequately answered using only LLM knowledge.

        Task:
        - Objective: \(task.objective)
        - Domain: \(task.persona.domain.rawValue)
        - Requirements: \(task.requirements.joined(separator: "; "))
        - Requires recent info: \(task.requiresRecentInfo)

        Consider:
        1. Does this require specific data, statistics, or facts that may not be in LLM training data?
        2. Does this require information from multiple authoritative sources?
        3. Would a web search significantly improve the answer quality?
        4. Is this a simple factual question that any LLM could answer?

        A task with high search necessity score (0.7+) should REQUIRE web search.
        A task with low search necessity score (<0.5) could be answered without search.

        Evaluate and provide your assessment.
        """

        let response = try await session.respond(generating: SearchNecessityResponse.self) {
            Prompt(prompt)
        }
        return response.content
    }
}

// MARK: - Convenience Extensions

extension TaskFilterStep {
    /// Filters tasks with default threshold.
    ///
    /// - Parameter tasks: Tasks to filter.
    /// - Returns: Filtered output.
    public func filter(_ tasks: [EvaluationTask]) async throws -> TaskFilterOutput {
        try await run(TaskFilterInput(tasks: tasks))
    }
}
