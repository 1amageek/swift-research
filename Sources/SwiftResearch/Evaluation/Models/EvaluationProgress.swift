import Foundation

/// Phase of the evaluation process.
public enum EvaluationPhase: String, Sendable, Codable {
    case taskConstruction = "Task Construction"
    case researchExecution = "Research Execution"
    case qualityEvaluation = "Quality Evaluation"
    case factChecking = "Fact Checking"
    case feedbackAnalysis = "Feedback Analysis"
    case autoTuning = "Auto-Tuning"
    case completed = "Completed"
}

/// Progress events for the evaluation pipeline.
public enum EvaluationProgress: Sendable {
    // MARK: - Overall Progress

    /// Evaluation has started.
    case started(taskId: UUID)

    /// Phase has changed.
    case phaseChanged(phase: EvaluationPhase)

    /// Evaluation has completed.
    case completed(result: EvaluationResult)

    /// An error occurred.
    case error(message: String)

    // MARK: - Task Construction Progress

    /// Personas are being generated.
    case personaGenerationStarted(domain: ResearchDomain)

    /// A persona was generated.
    case personaGenerated(persona: Persona)

    /// Tasks are being generated for a persona.
    case taskGenerationStarted(personaId: UUID)

    /// A task was generated.
    case taskGenerated(task: EvaluationTask)

    /// Task filtering has started.
    case taskFilteringStarted(totalTasks: Int)

    /// A task was filtered (qualified or disqualified).
    case taskFiltered(taskId: UUID, qualified: Bool, reason: String?)

    /// Task construction completed.
    case taskConstructionCompleted(qualifiedCount: Int, totalCount: Int)

    // MARK: - Quality Evaluation Progress

    /// Quality evaluation has started.
    case qualityEvaluationStarted

    /// Task-specific dimensions were generated.
    case dimensionsGenerated(dimensions: [QualityDimension])

    /// A dimension was scored.
    case dimensionScored(dimension: String, score: Int)

    /// Quality evaluation completed.
    case qualityEvaluationCompleted(result: QualityEvaluationResult)

    // MARK: - Fact Checking Progress

    /// Fact checking has started.
    case factCheckingStarted

    /// Statements were extracted.
    case statementsExtracted(count: Int)

    /// Evidence retrieval started for a statement.
    case evidenceRetrievalStarted(statementId: UUID)

    /// Evidence was retrieved for a statement.
    case evidenceRetrieved(statementId: UUID, evidenceCount: Int)

    /// A statement was verified.
    case statementVerified(statementId: UUID, verdict: FactVerdict)

    /// Fact checking completed.
    case factCheckingCompleted(result: FactCheckResult)

    // MARK: - Auto-Tuning Progress

    /// Feedback analysis has started.
    case feedbackAnalysisStarted

    /// Improvement suggestions were generated.
    case suggestionsGenerated(count: Int)

    /// A/B test has started.
    case abTestStarted(parameterName: String)

    /// A/B test completed.
    case abTestCompleted(parameterName: String, improvement: Double, accepted: Bool)

    /// Parameters were updated.
    case parametersUpdated(version: Int)

    /// Rollback was triggered.
    case rollbackTriggered(reason: String)
}

// MARK: - CustomStringConvertible

extension EvaluationProgress: CustomStringConvertible {
    public var description: String {
        switch self {
        case .started(let taskId):
            return "Evaluation started: \(taskId)"
        case .phaseChanged(let phase):
            return "Phase: \(phase.rawValue)"
        case .completed:
            return "Evaluation completed"
        case .error(let message):
            return "Error: \(message)"
        case .personaGenerationStarted(let domain):
            return "Generating personas for \(domain.rawValue)"
        case .personaGenerated(let persona):
            return "Generated persona: \(persona.role)"
        case .taskGenerationStarted(let personaId):
            return "Generating tasks for persona \(personaId)"
        case .taskGenerated(let task):
            return "Generated task: \(task.objective.prefix(30))..."
        case .taskFilteringStarted(let total):
            return "Filtering \(total) tasks"
        case .taskFiltered(let taskId, let qualified, let reason):
            let status = qualified ? "qualified" : "disqualified"
            let reasonStr = reason.map { ": \($0)" } ?? ""
            return "Task \(taskId) \(status)\(reasonStr)"
        case .taskConstructionCompleted(let qualified, let total):
            return "Task construction: \(qualified)/\(total) qualified"
        case .qualityEvaluationStarted:
            return "Quality evaluation started"
        case .dimensionsGenerated(let dimensions):
            return "Generated \(dimensions.count) dimensions"
        case .dimensionScored(let dimension, let score):
            return "\(dimension): \(score)/10"
        case .qualityEvaluationCompleted(let result):
            return "Quality: \(String(format: "%.1f", result.normalizedScore))/100"
        case .factCheckingStarted:
            return "Fact checking started"
        case .statementsExtracted(let count):
            return "Extracted \(count) statements"
        case .evidenceRetrievalStarted(let statementId):
            return "Retrieving evidence for \(statementId)"
        case .evidenceRetrieved(let statementId, let count):
            return "Retrieved \(count) evidence for \(statementId)"
        case .statementVerified(let statementId, let verdict):
            return "Verified \(statementId): \(verdict.rawValue)"
        case .factCheckingCompleted(let result):
            return "Accuracy: \(String(format: "%.1f", result.accuracy))%"
        case .feedbackAnalysisStarted:
            return "Analyzing feedback"
        case .suggestionsGenerated(let count):
            return "Generated \(count) suggestions"
        case .abTestStarted(let param):
            return "A/B testing: \(param)"
        case .abTestCompleted(let param, let improvement, let accepted):
            let status = accepted ? "accepted" : "rejected"
            return "A/B test \(param): \(String(format: "%.1f", improvement * 100))% (\(status))"
        case .parametersUpdated(let version):
            return "Parameters updated to v\(version)"
        case .rollbackTriggered(let reason):
            return "Rollback: \(reason)"
        }
    }
}
