import Foundation
import SwiftAgent

/// Research domain for persona categorization.
@Generable
public enum ResearchDomain: String, Sendable, Codable, CaseIterable {
    case technology = "Technology"
    case science = "Science"
    case medicine = "Medicine"
    case finance = "Finance"
    case law = "Law"
    case education = "Education"
    case business = "Business"
    case environment = "Environment"
    case politics = "Politics"
    case culture = "Culture"

    /// Description of the domain for LLM context.
    public var domainDescription: String {
        switch self {
        case .technology:
            return "Software development, AI, hardware, cybersecurity"
        case .science:
            return "Physics, chemistry, biology, astronomy"
        case .medicine:
            return "Healthcare, pharmaceuticals, medical research"
        case .finance:
            return "Investment, banking, cryptocurrency, economics"
        case .law:
            return "Legal regulations, compliance, court cases"
        case .education:
            return "Learning methods, academic research, educational policy"
        case .business:
            return "Startups, management, marketing, industry trends"
        case .environment:
            return "Climate change, sustainability, conservation"
        case .politics:
            return "Government policy, international relations, elections"
        case .culture:
            return "Arts, entertainment, social trends, history"
        }
    }
}

/// Expertise level of a persona.
@Generable
public enum ExpertiseLevel: String, Sendable, Codable, CaseIterable {
    case novice = "Novice"
    case intermediate = "Intermediate"
    case expert = "Expert"
    case professional = "Professional"
    case researcher = "Researcher"

    /// Expected depth of research for this expertise level.
    public var expectedDepth: String {
        switch self {
        case .novice:
            return "Basic overview with simple explanations"
        case .intermediate:
            return "Detailed information with some technical depth"
        case .expert:
            return "In-depth analysis with technical details"
        case .professional:
            return "Comprehensive analysis for decision-making"
        case .researcher:
            return "Academic-level depth with citations and methodology"
        }
    }
}

/// Represents a user persona for evaluation task generation.
///
/// Personas drive the generation of realistic research tasks by providing
/// context about who would ask such questions and what they need.
public struct Persona: Sendable, Identifiable, Codable, Hashable {
    /// Unique identifier for the persona.
    public let id: UUID

    /// The research domain this persona operates in.
    public let domain: ResearchDomain

    /// The role or job title of the persona.
    public let role: String

    /// The expertise level in their domain.
    public let expertise: ExpertiseLevel

    /// Specific information needs this persona typically has.
    public let informationNeeds: [String]

    /// Constraints or requirements for research output.
    public let constraints: [String]

    /// Creates a new persona.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - domain: The research domain.
    ///   - role: The role or job title.
    ///   - expertise: The expertise level.
    ///   - informationNeeds: Typical information needs.
    ///   - constraints: Output constraints.
    public init(
        id: UUID = UUID(),
        domain: ResearchDomain,
        role: String,
        expertise: ExpertiseLevel,
        informationNeeds: [String],
        constraints: [String]
    ) {
        self.id = id
        self.domain = domain
        self.role = role
        self.expertise = expertise
        self.informationNeeds = informationNeeds
        self.constraints = constraints
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Persona, rhs: Persona) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CustomStringConvertible

extension Persona: CustomStringConvertible {
    public var description: String {
        "\(role) (\(domain.rawValue), \(expertise.rawValue))"
    }
}
