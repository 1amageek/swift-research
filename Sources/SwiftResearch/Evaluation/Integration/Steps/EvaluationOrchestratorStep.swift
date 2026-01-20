import Foundation
import SwiftAgent

// MARK: - Input

/// Input for evaluation orchestration.
public struct EvaluationInput: Sendable {
    /// The evaluation task.
    public let task: EvaluationTask

    /// The research result to evaluate.
    public let researchResult: AggregatedResult

    /// Evaluation configuration.
    public let configuration: EvaluationConfiguration

    /// Creates a new evaluation input.
    ///
    /// - Parameters:
    ///   - task: The evaluation task.
    ///   - researchResult: The research result.
    ///   - configuration: Evaluation configuration.
    public init(
        task: EvaluationTask,
        researchResult: AggregatedResult,
        configuration: EvaluationConfiguration = .default
    ) {
        self.task = task
        self.researchResult = researchResult
        self.configuration = configuration
    }
}

// MARK: - EvaluationOrchestratorStep

/// A step that orchestrates the complete evaluation pipeline.
///
/// This step:
/// 1. Runs adaptive quality evaluation on the research output
/// 2. Runs active fact-checking on the research output
/// 3. Combines results into a comprehensive evaluation
///
/// Quality and fact-checking can run in parallel for efficiency.
///
/// ```swift
/// let step = EvaluationOrchestratorStep()
/// let result = try await step
///     .session(session)
///     .context(CrawlerConfiguration.self, value: config)
///     .run(EvaluationInput(task: task, researchResult: result))
/// ```
public struct EvaluationOrchestratorStep: Step, Sendable {
    public typealias Input = EvaluationInput
    public typealias Output = EvaluationResult

    @Session private var session: LanguageModelSession
    @Context private var crawlerConfig: CrawlerConfiguration

    /// Creates a new evaluation orchestrator step.
    public init() {}

    public func run(_ input: EvaluationInput) async throws -> EvaluationResult {
        let startedAt = Date()
        let config = input.configuration

        let researchOutput = input.researchResult.responseMarkdown

        if config.runEvaluationsInParallel {
            // Run quality evaluation and fact-checking in parallel
            async let qualityTask = runQualityEvaluation(
                task: input.task,
                researchOutput: researchOutput,
                config: config
            )
            async let factCheckTask = runFactChecking(
                researchOutput: researchOutput,
                config: config
            )

            let (qualityResult, factCheckResult) = try await (qualityTask, factCheckTask)

            return EvaluationResult(
                task: input.task,
                researchResult: input.researchResult,
                qualityResult: qualityResult,
                factCheckResult: factCheckResult,
                startedAt: startedAt,
                completedAt: Date(),
                qualityWeight: config.generalDimensionWeight,
                factualWeight: config.taskSpecificDimensionWeight
            )
        } else {
            // Run sequentially
            let qualityResult = try await runQualityEvaluation(
                task: input.task,
                researchOutput: researchOutput,
                config: config
            )

            let factCheckResult = try await runFactChecking(
                researchOutput: researchOutput,
                config: config
            )

            return EvaluationResult(
                task: input.task,
                researchResult: input.researchResult,
                qualityResult: qualityResult,
                factCheckResult: factCheckResult,
                startedAt: startedAt,
                completedAt: Date(),
                qualityWeight: config.generalDimensionWeight,
                factualWeight: config.taskSpecificDimensionWeight
            )
        }
    }

    // MARK: - Quality Evaluation

    private func runQualityEvaluation(
        task: EvaluationTask,
        researchOutput: String,
        config: EvaluationConfiguration
    ) async throws -> QualityEvaluationResult {
        let qualityStep = AdaptiveQualityStep()
            .session(session)

        return try await qualityStep.run(
            QualityEvaluationInput(
                task: task,
                researchOutput: researchOutput,
                generalWeight: config.generalDimensionWeight,
                maxTaskSpecificDimensions: config.maxTaskSpecificDimensions
            )
        )
    }

    // MARK: - Fact Checking

    private func runFactChecking(
        researchOutput: String,
        config: EvaluationConfiguration
    ) async throws -> FactCheckResult {
        let factCheckStep = FactCheckOrchestratorStep()
            .session(session)
            .context(crawlerConfig)

        return try await factCheckStep.run(
            FactCheckInput(
                researchOutput: researchOutput,
                maxStatements: config.maxStatementsToVerify,
                evidencePerStatement: config.evidencePerStatement,
                confidenceThreshold: config.verificationConfidenceThreshold
            )
        )
    }
}

// MARK: - Batch Evaluation

extension EvaluationOrchestratorStep {
    /// Evaluates multiple tasks and research results.
    ///
    /// Processes evaluations sequentially to avoid concurrency issues with @Session.
    ///
    /// - Parameter inputs: Array of evaluation inputs.
    /// - Returns: Batch evaluation result.
    public func evaluateBatch(_ inputs: [EvaluationInput]) async throws -> BatchEvaluationResult {
        var results: [EvaluationResult] = []

        for input in inputs {
            let result = try await run(input)
            results.append(result)
        }

        return BatchEvaluationResult(results: results)
    }
}
