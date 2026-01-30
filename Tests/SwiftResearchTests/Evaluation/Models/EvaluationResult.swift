import Foundation

/// Complete result of evaluating a research output.
public struct EvaluationResult: Sendable {
    /// The task that was evaluated.
    public let task: EvaluationTask

    /// The research output that was evaluated.
    public let researchResult: AggregatedResult

    /// Quality evaluation result.
    public let qualityResult: QualityEvaluationResult

    /// Fact checking result.
    public let factCheckResult: FactCheckResult

    /// Overall evaluation score (0-100).
    public let overallScore: Double

    /// Timestamp when evaluation started.
    public let startedAt: Date

    /// Timestamp when evaluation completed.
    public let completedAt: Date

    /// Duration of the evaluation.
    public var duration: Duration {
        .seconds(completedAt.timeIntervalSince(startedAt))
    }

    /// Creates a new evaluation result.
    ///
    /// - Parameters:
    ///   - task: The task that was evaluated.
    ///   - researchResult: The research output.
    ///   - qualityResult: Quality evaluation result.
    ///   - factCheckResult: Fact checking result.
    ///   - startedAt: When evaluation started.
    ///   - completedAt: When evaluation completed.
    ///   - qualityWeight: Weight for quality score (default 0.6).
    ///   - factualWeight: Weight for factual accuracy (default 0.4).
    public init(
        task: EvaluationTask,
        researchResult: AggregatedResult,
        qualityResult: QualityEvaluationResult,
        factCheckResult: FactCheckResult,
        startedAt: Date,
        completedAt: Date,
        qualityWeight: Double = 0.6,
        factualWeight: Double = 0.4
    ) {
        self.task = task
        self.researchResult = researchResult
        self.qualityResult = qualityResult
        self.factCheckResult = factCheckResult
        self.startedAt = startedAt
        self.completedAt = completedAt

        // Calculate overall score: weighted combination of quality and factual accuracy
        self.overallScore = (qualityResult.normalizedScore * qualityWeight)
            + (factCheckResult.accuracy * factualWeight)
    }

    /// Quality score only.
    public var qualityScore: Double {
        qualityResult.normalizedScore
    }

    /// Factual accuracy only.
    public var factualAccuracy: Double {
        factCheckResult.accuracy
    }

    /// Whether this evaluation passes minimum quality thresholds.
    ///
    /// - Parameters:
    ///   - minQuality: Minimum quality score (default 60).
    ///   - minAccuracy: Minimum factual accuracy (default 70).
    /// - Returns: True if both thresholds are met.
    public func passesThreshold(minQuality: Double = 60.0, minAccuracy: Double = 70.0) -> Bool {
        qualityScore >= minQuality && factualAccuracy >= minAccuracy
    }
}

// MARK: - CustomStringConvertible

extension EvaluationResult: CustomStringConvertible {
    public var description: String {
        """
        Evaluation Result:
          Overall: \(String(format: "%.1f", overallScore))/100
          Quality: \(String(format: "%.1f", qualityScore))/100
          Accuracy: \(String(format: "%.1f", factualAccuracy))%
          Duration: \(String(format: "%.1f", completedAt.timeIntervalSince(startedAt)))s
        """
    }
}

// MARK: - Batch Evaluation Result

/// Result of evaluating multiple tasks.
public struct BatchEvaluationResult: Sendable {
    /// Individual evaluation results.
    public let results: [EvaluationResult]

    /// Average overall score.
    public let averageOverallScore: Double

    /// Average quality score.
    public let averageQualityScore: Double

    /// Average factual accuracy.
    public let averageFactualAccuracy: Double

    /// Standard deviation of overall scores.
    public let scoreStdDev: Double

    /// Number of evaluations that passed thresholds.
    public let passedCount: Int

    /// Pass rate percentage.
    public let passRate: Double

    /// Total duration of all evaluations.
    public let totalDuration: Duration

    /// Creates a new batch evaluation result.
    ///
    /// - Parameter results: Individual evaluation results.
    public init(results: [EvaluationResult]) {
        self.results = results

        let count = Double(results.count)
        guard count > 0 else {
            self.averageOverallScore = 0
            self.averageQualityScore = 0
            self.averageFactualAccuracy = 0
            self.scoreStdDev = 0
            self.passedCount = 0
            self.passRate = 0
            self.totalDuration = .zero
            return
        }

        // Calculate averages
        let avgOverall = results.reduce(0.0) { $0 + $1.overallScore } / count
        let avgQuality = results.reduce(0.0) { $0 + $1.qualityScore } / count
        let avgAccuracy = results.reduce(0.0) { $0 + $1.factualAccuracy } / count

        self.averageOverallScore = avgOverall
        self.averageQualityScore = avgQuality
        self.averageFactualAccuracy = avgAccuracy

        // Calculate standard deviation
        let variance = results.reduce(0.0) { sum, result in
            let diff = result.overallScore - avgOverall
            return sum + (diff * diff)
        } / count
        self.scoreStdDev = sqrt(variance)

        // Count passed evaluations
        self.passedCount = results.filter { $0.passesThreshold() }.count
        self.passRate = Double(passedCount) / count * 100.0

        // Sum durations
        let totalSeconds = results.reduce(0.0) { $0 + $1.completedAt.timeIntervalSince($1.startedAt) }
        self.totalDuration = .seconds(totalSeconds)
    }

    /// Results sorted by overall score (descending).
    public var sortedByScore: [EvaluationResult] {
        results.sorted { $0.overallScore > $1.overallScore }
    }

    /// Results that failed to pass thresholds.
    public var failedResults: [EvaluationResult] {
        results.filter { !$0.passesThreshold() }
    }

    /// Results grouped by task difficulty.
    public func resultsByDifficulty() -> [DifficultyLevel: [EvaluationResult]] {
        Dictionary(grouping: results) { $0.task.difficulty }
    }

    /// Results grouped by domain.
    public func resultsByDomain() -> [ResearchDomain: [EvaluationResult]] {
        Dictionary(grouping: results) { $0.task.persona.domain }
    }
}

// MARK: - CustomStringConvertible

extension BatchEvaluationResult: CustomStringConvertible {
    public var description: String {
        """
        Batch Evaluation (\(results.count) tasks):
          Average Score: \(String(format: "%.1f", averageOverallScore))/100 (σ=\(String(format: "%.1f", scoreStdDev)))
          Quality: \(String(format: "%.1f", averageQualityScore))/100
          Accuracy: \(String(format: "%.1f", averageFactualAccuracy))%
          Pass Rate: \(String(format: "%.1f", passRate))% (\(passedCount)/\(results.count))
        """
    }
}
