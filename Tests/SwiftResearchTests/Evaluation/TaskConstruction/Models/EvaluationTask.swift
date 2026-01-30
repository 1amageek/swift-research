import Foundation
import SwiftAgent

/// Expected output format for a research task.
@Generable
public enum OutputFormat: String, Sendable, Codable, CaseIterable {
    case report = "Report"
    case summary = "Summary"
    case comparison = "Comparison"
    case analysis = "Analysis"
    case recommendation = "Recommendation"
    case tutorial = "Tutorial"

    /// Description of what this format entails.
    public var formatDescription: String {
        switch self {
        case .report:
            return "Comprehensive report with sections and evidence"
        case .summary:
            return "Concise summary of key points"
        case .comparison:
            return "Side-by-side comparison of options"
        case .analysis:
            return "Deep analysis of a topic or situation"
        case .recommendation:
            return "Actionable recommendations with rationale"
        case .tutorial:
            return "Step-by-step guide or explanation"
        }
    }
}

/// Difficulty level of an evaluation task.
@Generable
public enum DifficultyLevel: String, Sendable, Codable, CaseIterable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
    case expert = "Expert"

    /// Expected number of sources needed.
    public var expectedSources: Int {
        switch self {
        case .easy: return 3
        case .medium: return 5
        case .hard: return 10
        case .expert: return 15
        }
    }
}

/// Qualification status of an evaluation task.
public enum QualificationStatus: String, Sendable, Codable {
    /// Task has not been evaluated yet.
    case pending = "Pending"
    /// Task passed qualification filters.
    case qualified = "Qualified"
    /// Task failed qualification filters.
    case disqualified = "Disqualified"
}

/// A research task for evaluating deep research systems.
///
/// Tasks are generated from personas and filtered to ensure they require
/// actual web research (not solvable by LLM parametric knowledge alone).
public struct EvaluationTask: Sendable, Identifiable, Codable, Hashable {
    /// Unique identifier for the task.
    public let id: UUID

    /// The persona that would ask this question.
    public let persona: Persona

    /// The research objective (question to answer).
    public let objective: String

    /// Specific requirements for the research output.
    public let requirements: [String]

    /// Expected output format.
    public let expectedFormat: OutputFormat

    /// Difficulty level of the task.
    public let difficulty: DifficultyLevel

    /// Whether the task requires up-to-date information.
    public var requiresRecentInfo: Bool

    /// Score indicating how much web search is necessary (0.0-1.0).
    /// Higher means more search is needed.
    public var searchNecessityScore: Double

    /// Current qualification status.
    public var qualificationStatus: QualificationStatus

    /// Reason for disqualification, if applicable.
    public var disqualificationReason: String?

    /// Timestamp when the task was created.
    public let createdAt: Date

    /// Creates a new evaluation task.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - persona: The persona that would ask this question.
    ///   - objective: The research objective.
    ///   - requirements: Specific requirements.
    ///   - expectedFormat: Expected output format.
    ///   - difficulty: Difficulty level.
    ///   - requiresRecentInfo: Whether recent info is needed.
    ///   - searchNecessityScore: How much search is necessary.
    ///   - qualificationStatus: Current status. Defaults to pending.
    ///   - disqualificationReason: Reason if disqualified.
    ///   - createdAt: Creation timestamp. Defaults to now.
    public init(
        id: UUID = UUID(),
        persona: Persona,
        objective: String,
        requirements: [String],
        expectedFormat: OutputFormat,
        difficulty: DifficultyLevel,
        requiresRecentInfo: Bool,
        searchNecessityScore: Double = 0.0,
        qualificationStatus: QualificationStatus = .pending,
        disqualificationReason: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.persona = persona
        self.objective = objective
        self.requirements = requirements
        self.expectedFormat = expectedFormat
        self.difficulty = difficulty
        self.requiresRecentInfo = requiresRecentInfo
        self.searchNecessityScore = searchNecessityScore
        self.qualificationStatus = qualificationStatus
        self.disqualificationReason = disqualificationReason
        self.createdAt = createdAt
    }

    /// Whether this task is ready for evaluation.
    public var isQualified: Bool {
        qualificationStatus == .qualified
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: EvaluationTask, rhs: EvaluationTask) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CustomStringConvertible

extension EvaluationTask: CustomStringConvertible {
    public var description: String {
        "[\(difficulty.rawValue)] \(objective.prefix(50))... (\(persona.role))"
    }
}
