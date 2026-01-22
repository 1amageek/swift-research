import Foundation
import SwiftAgent

// MARK: - Input

/// Input for persona generation.
public struct PersonaGenerationInput: Sendable {
    /// The research domain to generate personas for.
    public let domain: ResearchDomain

    /// Number of personas to generate.
    public let count: Int

    /// Creates a new persona generation input.
    ///
    /// - Parameters:
    ///   - domain: The research domain.
    ///   - count: Number of personas to generate.
    public init(domain: ResearchDomain, count: Int = 5) {
        self.domain = domain
        self.count = count
    }
}

// MARK: - PersonaGeneratorStep

/// A step that generates diverse research personas for a given domain.
///
/// Uses LLM to create personas with varying expertise levels, information needs,
/// and constraints to ensure comprehensive evaluation coverage.
///
/// ```swift
/// let step = PersonaGeneratorStep()
/// let personas = try await step
///     .session(session)
///     .run(PersonaGenerationInput(domain: .technology, count: 5))
/// ```
public struct PersonaGeneratorStep: Step, Sendable {
    public typealias Input = PersonaGenerationInput
    public typealias Output = [Persona]

    @Session private var session: LanguageModelSession

    /// Creates a new persona generator step.
    public init() {}

    public func run(_ input: PersonaGenerationInput) async throws -> [Persona] {
        let prompt = buildPrompt(for: input)

        let generateStep = Generate<String, PersonaGenerationResponse>(
            session: session,
            prompt: { Prompt($0) }
        )
        let response = try await generateStep.run(prompt)

        return response.personas.map { generated in
            Persona(
                domain: input.domain,
                role: generated.role,
                expertise: generated.expertiseLevel,
                informationNeeds: generated.informationNeeds,
                constraints: generated.constraints
            )
        }
    }

    private func buildPrompt(for input: PersonaGenerationInput) -> String {
        return """
        Generate \(input.count) diverse research personas for the \(input.domain.rawValue) domain.

        Each persona should represent a realistic user who would need to conduct deep research in this domain.

        Requirements:
        - Vary expertise levels (beginner, intermediate, advanced, expert)
        - Include different roles and perspectives
        - Make information needs specific and actionable
        - Include realistic constraints (time, language, technical background)

        Domain: \(input.domain.rawValue)
        Domain description: \(input.domain.domainDescription)

        Generate personas that would have genuinely different research needs and approaches.
        """
    }
}

// MARK: - Batch Generation

extension PersonaGeneratorStep {
    /// Generates personas for multiple domains.
    ///
    /// - Parameters:
    ///   - domains: The domains to generate personas for.
    ///   - personasPerDomain: Number of personas per domain.
    /// - Returns: Dictionary mapping domains to their personas.
    public func generateForDomains(
        _ domains: [ResearchDomain],
        personasPerDomain: Int = 5
    ) async throws -> [ResearchDomain: [Persona]] {
        var result: [ResearchDomain: [Persona]] = [:]

        for domain in domains {
            let input = PersonaGenerationInput(domain: domain, count: personasPerDomain)
            let personas = try await run(input)
            result[domain] = personas
        }

        return result
    }
}

