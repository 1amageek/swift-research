import Foundation

// MARK: - A/B Test Configuration

/// Configuration for an A/B test.
public struct ABTestConfiguration: Sendable, Codable {
    /// Name of the parameter being tested.
    public let parameterName: String

    /// Baseline value (current).
    public let baselineValue: String

    /// Variant value (proposed).
    public let variantValue: String

    /// Number of tasks to use for the test.
    public let sampleSize: Int

    /// Minimum improvement percentage to accept the variant.
    public let minImprovementThreshold: Double

    /// Creates a new A/B test configuration.
    public init(
        parameterName: String,
        baselineValue: String,
        variantValue: String,
        sampleSize: Int = 10,
        minImprovementThreshold: Double = 0.01
    ) {
        self.parameterName = parameterName
        self.baselineValue = baselineValue
        self.variantValue = variantValue
        self.sampleSize = sampleSize
        self.minImprovementThreshold = minImprovementThreshold
    }
}

// MARK: - A/B Test Result

/// Result of an A/B test.
public struct ABTestResult: Sendable, Codable {
    /// The test configuration.
    public let configuration: ABTestConfiguration

    /// Baseline evaluation results.
    public let baselineScores: [Double]

    /// Variant evaluation results.
    public let variantScores: [Double]

    /// Average baseline score.
    public let baselineAverage: Double

    /// Variant average score.
    public let variantAverage: Double

    /// Improvement percentage (variant - baseline) / baseline.
    public let improvementPercentage: Double

    /// Whether the improvement is statistically significant.
    public let isStatisticallySignificant: Bool

    /// P-value from statistical test.
    public let pValue: Double

    /// Whether the variant should be accepted.
    public let shouldAccept: Bool

    /// Timestamp when the test was completed.
    public let completedAt: Date

    /// Creates a new A/B test result.
    public init(
        configuration: ABTestConfiguration,
        baselineScores: [Double],
        variantScores: [Double],
        completedAt: Date = Date()
    ) {
        self.configuration = configuration
        self.baselineScores = baselineScores
        self.variantScores = variantScores
        self.completedAt = completedAt

        // Calculate averages
        self.baselineAverage = baselineScores.isEmpty ? 0 : baselineScores.reduce(0, +) / Double(baselineScores.count)
        self.variantAverage = variantScores.isEmpty ? 0 : variantScores.reduce(0, +) / Double(variantScores.count)

        // Calculate improvement
        self.improvementPercentage = baselineAverage > 0
            ? (variantAverage - baselineAverage) / baselineAverage
            : 0

        // Perform Welch's t-test for statistical significance
        let (pVal, isSignificant) = Self.welchTTest(
            sample1: baselineScores,
            sample2: variantScores,
            alpha: 0.05
        )
        self.pValue = pVal
        self.isStatisticallySignificant = isSignificant

        // Accept if improvement is significant and above threshold
        self.shouldAccept = isSignificant
            && improvementPercentage >= configuration.minImprovementThreshold
    }

    /// Performs Welch's t-test.
    private static func welchTTest(
        sample1: [Double],
        sample2: [Double],
        alpha: Double
    ) -> (pValue: Double, isSignificant: Bool) {
        guard sample1.count >= 2, sample2.count >= 2 else {
            return (1.0, false)
        }

        let n1 = Double(sample1.count)
        let n2 = Double(sample2.count)

        let mean1 = sample1.reduce(0, +) / n1
        let mean2 = sample2.reduce(0, +) / n2

        let var1 = sample1.reduce(0) { $0 + ($1 - mean1) * ($1 - mean1) } / (n1 - 1)
        let var2 = sample2.reduce(0) { $0 + ($1 - mean2) * ($1 - mean2) } / (n2 - 1)

        let se1 = var1 / n1
        let se2 = var2 / n2
        let se = sqrt(se1 + se2)

        guard se > 0 else {
            return (1.0, false)
        }

        let t = (mean2 - mean1) / se

        // Approximate p-value using normal distribution
        // For a proper implementation, use a t-distribution
        let pValue = 2 * (1 - Self.normalCDF(abs(t)))

        return (pValue, pValue < alpha)
    }

    /// Normal CDF approximation.
    private static func normalCDF(_ x: Double) -> Double {
        // Approximation using error function
        let sign = x < 0 ? -1.0 : 1.0
        let absX = abs(x)

        // Constants for approximation
        let a1 = 0.254829592
        let a2 = -0.284496736
        let a3 = 1.421413741
        let a4 = -1.453152027
        let a5 = 1.061405429
        let p = 0.3275911

        let t = 1.0 / (1.0 + p * absX / sqrt(2.0))
        let y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-absX * absX / 2.0)

        return 0.5 * (1.0 + sign * y)
    }
}

// MARK: - CustomStringConvertible

extension ABTestResult: CustomStringConvertible {
    public var description: String {
        """
        A/B Test: \(configuration.parameterName)
          Baseline: \(String(format: "%.2f", baselineAverage)) (\(configuration.baselineValue))
          Variant:  \(String(format: "%.2f", variantAverage)) (\(configuration.variantValue))
          Improvement: \(String(format: "%.1f", improvementPercentage * 100))%
          P-value: \(String(format: "%.4f", pValue))
          Decision: \(shouldAccept ? "ACCEPT" : "REJECT")
        """
    }
}

// MARK: - Tuning Result

/// Result of an auto-tuning cycle.
public enum TuningResult: Sendable {
    /// Parameters were improved.
    case improved(ABTestResult)

    /// No improvement found.
    case noChange(reason: String)

    /// Rollback was triggered due to degradation.
    case rollback(previousVersion: Int, reason: String)

    /// Error occurred during tuning.
    case error(message: String)
}
