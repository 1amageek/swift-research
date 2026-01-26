import Foundation
import SwiftAgent

/// Type of verifiable statement.
/// Case names are kept simple to match LLM natural output patterns.
@Generable
public enum StatementType: String, Sendable, Codable, CaseIterable {
    /// Numbers, statistics, quantities.
    case numeric = "numeric"

    /// Dates, time periods, events.
    case temporal = "temporal"

    /// Named entities, relationships.
    case entity = "entity"

    /// Cause-effect relationships.
    case causal = "causal"

    /// Comparisons between entities.
    case comparative = "comparative"

    /// Description of this statement type.
    public var typeDescription: String {
        switch self {
        case .numeric:
            return "Claims involving numbers, statistics, percentages, or quantities"
        case .temporal:
            return "Claims about dates, time periods, or when events occurred"
        case .entity:
            return "Claims about named entities, their properties, or relationships"
        case .causal:
            return "Claims about cause-and-effect relationships"
        case .comparative:
            return "Claims comparing two or more entities"
        }
    }

    /// Example of this statement type.
    public var example: String {
        switch self {
        case .numeric:
            return "The population is 14 million"
        case .temporal:
            return "The product was released in 2024"
        case .entity:
            return "Apple acquired the company"
        case .causal:
            return "This led to improved performance"
        case .comparative:
            return "System A is faster than System B"
        }
    }
}

/// A verifiable statement extracted from research output.
///
/// Statements are extracted from the response and verified against
/// evidence retrieved from the web.
public struct VerifiableStatement: Sendable, Identifiable, Codable, Hashable {
    /// Unique identifier for the statement.
    public let id: UUID

    /// The statement text to verify.
    public let text: String

    /// Type of the statement.
    public let type: StatementType

    /// Section of the source document where this was found.
    public let sourceSection: String

    /// Confidence that this statement is actually verifiable (0.0-1.0).
    public let verifiabilityConfidence: Double

    /// LLM-suggested search query for verification.
    /// This is the query that the extraction model recommended for verifying this statement.
    public let suggestedSearchQuery: String?

    /// Line number in the original document (if available).
    public let lineNumber: Int?

    /// Creates a new verifiable statement.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - text: The statement text.
    ///   - type: Type of statement.
    ///   - sourceSection: Source section name.
    ///   - verifiabilityConfidence: How confident we are this can be verified.
    ///   - suggestedSearchQuery: LLM-suggested search query for verification.
    ///   - lineNumber: Line number in source document.
    public init(
        id: UUID = UUID(),
        text: String,
        type: StatementType,
        sourceSection: String,
        verifiabilityConfidence: Double,
        suggestedSearchQuery: String? = nil,
        lineNumber: Int? = nil
    ) {
        self.id = id
        self.text = text
        self.type = type
        self.sourceSection = sourceSection
        self.verifiabilityConfidence = max(0.0, min(1.0, verifiabilityConfidence))
        self.suggestedSearchQuery = suggestedSearchQuery
        self.lineNumber = lineNumber
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: VerifiableStatement, rhs: VerifiableStatement) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CustomStringConvertible

extension VerifiableStatement: CustomStringConvertible {
    public var description: String {
        "[\(type.rawValue)] \(text.prefix(60))..."
    }
}
