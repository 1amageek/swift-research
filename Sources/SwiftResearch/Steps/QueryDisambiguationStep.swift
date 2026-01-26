import Foundation
import SwiftAgent

/// Input for query disambiguation.
public struct QueryDisambiguationInput: Sendable {
    /// The original search query.
    public let query: String

    /// Whether to enable verbose logging.
    public let verbose: Bool

    public init(query: String, verbose: Bool = false) {
        self.query = query
        self.verbose = verbose
    }
}

/// Step that rewrites ambiguous queries using domain context.
///
/// When a query could have multiple interpretations (e.g., "What is Swift?" could mean
/// Swift programming language or SWIFT financial network), this step uses the domain
/// context to generate an unambiguous search query.
///
/// ## Example
///
/// ```swift
/// // Run within context that provides ModelContext and config
/// let input = QueryDisambiguationInput(query: "What is Swift?")
/// let disambiguated = try await QueryDisambiguationStep().run(input)
/// // Returns: "Swift programming language Apple iOS development"
/// ```
public struct QueryDisambiguationStep: Step, Sendable {
    public typealias Input = QueryDisambiguationInput
    public typealias Output = String

    @Context var modelContext: ModelContext
    @Context var config: CrawlerConfiguration

    public init() {}

    public func run(_ input: QueryDisambiguationInput) async throws -> String {
        // If no domain context, return query as-is
        guard let domainContext = config.domainContext, !domainContext.isEmpty else {
            if input.verbose {
                printFlush("[QueryDisambiguation] No domain context, using original query")
            }
            return input.query
        }

        let session = LanguageModelSession(
            model: modelContext.model,
            tools: [],
            instructions: StepInstructions.queryDisambiguation
        )

        let prompt = """
        Rewrite the following search query to be unambiguous within the given domain context.

        Original query: \(input.query)
        Domain context: \(domainContext)

        Instructions:
        - If the query contains ambiguous terms, clarify them based on the domain context
        - Add relevant keywords that help search engines find domain-appropriate results
        - Keep the query concise and suitable for web search
        - Return ONLY the rewritten search query, nothing else
        - If the query is already unambiguous within the domain, return it as-is
        """

        if input.verbose {
            printFlush("[QueryDisambiguation] Original query: \(input.query)")
            printFlush("[QueryDisambiguation] Domain context: \(domainContext)")
        }

        do {
            let response = try await session.respond {
                Prompt(prompt)
            }

            let disambiguatedQuery = response.content
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")  // Remove quotes if any

            if input.verbose {
                printFlush("[QueryDisambiguation] Disambiguated query: \(disambiguatedQuery)")
            }

            // Sanity check: if response is empty or too long, use original
            if disambiguatedQuery.isEmpty || disambiguatedQuery.count > 200 {
                return input.query
            }

            return disambiguatedQuery
        } catch {
            // On error, fall back to original query
            if input.verbose {
                printFlush("[QueryDisambiguation] Error: \(error), using original query")
            }
            return input.query
        }
    }
}
