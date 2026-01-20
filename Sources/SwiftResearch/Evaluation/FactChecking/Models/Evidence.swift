import Foundation
import SwiftAgent

/// Level of support an evidence provides for a statement.
@Generable
public enum SupportLevel: String, Sendable, Codable, CaseIterable {
    /// Strong support for the statement.
    case strongSupport = "Strong Support"

    /// Weak or partial support.
    case weakSupport = "Weak Support"

    /// Neither supports nor contradicts.
    case neutral = "Neutral"

    /// Weak contradiction of the statement.
    case weakContradict = "Weak Contradict"

    /// Strong contradiction of the statement.
    case strongContradict = "Strong Contradict"

    /// Numeric weight for aggregation (-1.0 to 1.0).
    public var weight: Double {
        switch self {
        case .strongSupport: return 1.0
        case .weakSupport: return 0.5
        case .neutral: return 0.0
        case .weakContradict: return -0.5
        case .strongContradict: return -1.0
        }
    }
}

/// Evidence retrieved for fact verification.
///
/// Evidence is collected from web searches and used to verify
/// statements in the research output.
public struct Evidence: Sendable, Identifiable, Codable, Hashable {
    /// Unique identifier for the evidence.
    public let id: UUID

    /// URL of the source.
    public let sourceURL: URL

    /// Title of the source page.
    public let sourceTitle: String

    /// Relevant text excerpt from the source.
    public let relevantText: String

    /// How well this evidence supports/contradicts the statement.
    public let supportLevel: SupportLevel

    /// Timestamp when this evidence was retrieved.
    public let retrievedAt: Date

    /// Credibility score of the source (0.0-1.0).
    public let sourceCredibility: Double

    /// Creates new evidence.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - sourceURL: URL of the source.
    ///   - sourceTitle: Title of the source page.
    ///   - relevantText: Relevant text excerpt.
    ///   - supportLevel: How well this supports the statement.
    ///   - retrievedAt: When this was retrieved. Defaults to now.
    ///   - sourceCredibility: Credibility of the source.
    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceTitle: String,
        relevantText: String,
        supportLevel: SupportLevel,
        retrievedAt: Date = Date(),
        sourceCredibility: Double = 0.5
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.relevantText = relevantText
        self.supportLevel = supportLevel
        self.retrievedAt = retrievedAt
        self.sourceCredibility = max(0.0, min(1.0, sourceCredibility))
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Evidence, rhs: Evidence) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CustomStringConvertible

extension Evidence: CustomStringConvertible {
    public var description: String {
        "[\(supportLevel.rawValue)] \(sourceTitle.prefix(40))..."
    }
}
