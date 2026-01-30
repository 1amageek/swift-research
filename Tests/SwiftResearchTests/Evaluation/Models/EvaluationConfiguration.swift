import Foundation
import SwiftAgent

/// Configuration for the evaluation framework.
@Contextable
public struct EvaluationConfiguration: Sendable {
    // MARK: - Task Construction

    /// Domains to use for persona generation.
    public let domainsToUse: [ResearchDomain]

    /// Number of personas to generate per domain.
    public let personasPerDomain: Int

    /// Number of tasks to generate per persona.
    public let tasksPerPersona: Int

    /// Minimum search necessity score for task qualification (0.0-1.0).
    public let qualificationThreshold: Double

    // MARK: - Quality Evaluation

    /// Weight for general dimensions vs task-specific.
    public let generalDimensionWeight: Double

    /// Weight for task-specific dimensions.
    public let taskSpecificDimensionWeight: Double

    /// Maximum number of task-specific dimensions to generate.
    public let maxTaskSpecificDimensions: Int

    // MARK: - Fact Checking

    /// Maximum number of statements to verify per evaluation.
    public let maxStatementsToVerify: Int

    /// Number of evidence pieces to retrieve per statement.
    public let evidencePerStatement: Int

    /// Minimum confidence threshold for verification (0.0-1.0).
    public let verificationConfidenceThreshold: Double

    // MARK: - Integration

    /// Whether to run quality and fact-checking in parallel.
    public let runEvaluationsInParallel: Bool

    /// Whether to enable the auto-tuning feedback loop.
    public let autoTuningEnabled: Bool

    /// Minimum improvement percentage to accept a parameter change.
    public let minImprovementThreshold: Double

    /// Maximum degradation percentage before rollback.
    public let maxDegradationThreshold: Double

    // MARK: - Performance

    /// Timeout for individual evaluation operations.
    public let operationTimeout: Duration

    /// Creates a new evaluation configuration.
    public init(
        domainsToUse: [ResearchDomain] = ResearchDomain.allCases,
        personasPerDomain: Int = 5,
        tasksPerPersona: Int = 4,
        qualificationThreshold: Double = 0.7,
        generalDimensionWeight: Double = 0.6,
        taskSpecificDimensionWeight: Double = 0.4,
        maxTaskSpecificDimensions: Int = 3,
        maxStatementsToVerify: Int = 20,
        evidencePerStatement: Int = 3,
        verificationConfidenceThreshold: Double = 0.7,
        runEvaluationsInParallel: Bool = false,
        autoTuningEnabled: Bool = true,
        minImprovementThreshold: Double = 0.01,
        maxDegradationThreshold: Double = 0.05,
        operationTimeout: Duration = .seconds(60)
    ) {
        self.domainsToUse = domainsToUse
        self.personasPerDomain = personasPerDomain
        self.tasksPerPersona = tasksPerPersona
        self.qualificationThreshold = qualificationThreshold
        self.generalDimensionWeight = generalDimensionWeight
        self.taskSpecificDimensionWeight = taskSpecificDimensionWeight
        self.maxTaskSpecificDimensions = maxTaskSpecificDimensions
        self.maxStatementsToVerify = maxStatementsToVerify
        self.evidencePerStatement = evidencePerStatement
        self.verificationConfidenceThreshold = verificationConfidenceThreshold
        self.runEvaluationsInParallel = runEvaluationsInParallel
        self.autoTuningEnabled = autoTuningEnabled
        self.minImprovementThreshold = minImprovementThreshold
        self.maxDegradationThreshold = maxDegradationThreshold
        self.operationTimeout = operationTimeout
    }

    /// Default configuration.
    public static let `default` = EvaluationConfiguration()

    /// The default value for Contextable conformance.
    public static var defaultValue: EvaluationConfiguration { .default }

    /// Expected total number of tasks to generate.
    public var expectedTaskCount: Int {
        domainsToUse.count * personasPerDomain * tasksPerPersona
    }

    /// Expected number of qualified tasks (after filtering).
    public var expectedQualifiedTaskCount: Int {
        // Assume roughly 50% pass both filters
        expectedTaskCount / 2
    }
}
