import Foundation
import SwiftAgent

// MARK: - ABTestRunner

/// Runs A/B tests to compare baseline and variant configurations.
///
/// Executes the same evaluation tasks with different configurations
/// and compares the results to determine if the variant is an improvement.
public struct ABTestRunner: Sendable {
    @Session private var session: LanguageModelSession
    @Context private var modelContext: ModelContext
    @Context private var crawlerConfig: CrawlerConfiguration

    /// The A/B test configuration.
    public let configuration: ABTestConfiguration

    /// Creates a new A/B test runner.
    ///
    /// - Parameter configuration: The test configuration.
    public init(configuration: ABTestConfiguration) {
        self.configuration = configuration
    }

    /// Runs the A/B test with the provided test cases.
    ///
    /// - Parameter testCases: Array of (task, researchResult) pairs to test.
    /// - Returns: The A/B test result.
    public func run(
        testCases: [(task: EvaluationTask, result: AggregatedResult)]
    ) async throws -> ABTestResult {
        let samplesToRun = min(configuration.sampleSize, testCases.count)

        guard samplesToRun > 0 else {
            return ABTestResult(
                configuration: configuration,
                baselineScores: [],
                variantScores: []
            )
        }

        let selectedCases = Array(testCases.shuffled().prefix(samplesToRun))

        var baselineScores: [Double] = []
        var variantScores: [Double] = []

        // Run evaluations for each test case
        for (task, researchResult) in selectedCases {
            // Run baseline evaluation
            let baselineScore = try await runEvaluation(
                task: task,
                researchResult: researchResult,
                parameterValue: configuration.baselineValue
            )
            baselineScores.append(baselineScore)

            // Run variant evaluation
            let variantScore = try await runEvaluation(
                task: task,
                researchResult: researchResult,
                parameterValue: configuration.variantValue
            )
            variantScores.append(variantScore)
        }

        return ABTestResult(
            configuration: configuration,
            baselineScores: baselineScores,
            variantScores: variantScores
        )
    }

    private func runEvaluation(
        task: EvaluationTask,
        researchResult: AggregatedResult,
        parameterValue: String
    ) async throws -> Double {
        // Create evaluation input with the specified parameter
        let input = EvaluationInput(
            task: task,
            researchResult: researchResult,
            configuration: .default
        )

        let orchestrator = EvaluationOrchestratorStep()
            .session(session)
            .context(modelContext)
            .context(crawlerConfig)

        let result = try await orchestrator.run(input)
        return result.overallScore
    }
}


// MARK: - A/B Test Report

/// A report summarizing multiple A/B test results.
public struct ABTestReport: Sendable {
    /// All test results.
    public let results: [ABTestResult]

    /// Tests that showed significant improvement.
    public var successfulTests: [ABTestResult] {
        results.filter { $0.shouldAccept }
    }

    /// Tests that showed no improvement or degradation.
    public var failedTests: [ABTestResult] {
        results.filter { !$0.shouldAccept }
    }

    /// Overall improvement rate.
    public var improvementRate: Double {
        guard !results.isEmpty else { return 0 }
        return Double(successfulTests.count) / Double(results.count) * 100
    }

    /// Average improvement across successful tests.
    public var averageImprovement: Double {
        guard !successfulTests.isEmpty else { return 0 }
        return successfulTests.reduce(0) { $0 + $1.improvementPercentage } / Double(successfulTests.count)
    }

    /// Creates a report from test results.
    ///
    /// - Parameter results: The test results.
    public init(results: [ABTestResult]) {
        self.results = results
    }
}

// MARK: - CustomStringConvertible

extension ABTestReport: CustomStringConvertible {
    public var description: String {
        """
        A/B Test Report:
          Total Tests: \(results.count)
          Successful: \(successfulTests.count) (\(String(format: "%.1f", improvementRate))%)
          Failed: \(failedTests.count)
          Average Improvement: \(String(format: "%.2f", averageImprovement * 100))%
        """
    }
}
