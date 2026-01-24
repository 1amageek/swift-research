import Foundation
import SwiftAgent

/// Phase 0.5: Query Understanding Step.
///
/// Extracts the main subject/topic from the user's query, separating
/// it from action words like "research", "explain", "tell me", etc.
///
/// ## Example
///
/// ```swift
/// // Run within context that provides ModelContext
/// try await withContext(ModelContext.self, value: ModelContext(model)) {
///     let context = try await QueryUnderstandingStep().run("京都について調査してください")
///     // context.subject == "京都"
/// }
/// ```
public struct QueryUnderstandingStep: Step, Sendable {
    public typealias Input = String
    public typealias Output = QueryContext

    @Context var modelContext: ModelContext

    /// Whether to enable verbose logging.
    private let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    public func run(_ query: String) async throws -> QueryContext {
        let session = LanguageModelSession(
            model: modelContext.model,
            tools: [],
            instructions: StepInstructions.queryUnderstanding
        )

        let prompt = """
        # User Query
        \(query)

        # Task
        1. Extract the main subject/topic from this query (what the user wants to know about)
        2. Explain WHY you extracted this subject

        Rules:
        - Do NOT include action words as subject (research, explain, investigate, tell, search, 調査, 教えて, 説明, etc.)
        - The reasoning should explain what the action words were and why the subject is the topic, not the action

        IMPORTANT: Output JSON only.
        """

        if verbose {
            printFlush("┌─── LLM INPUT (QueryUnderstanding) ───")
            printFlush(prompt)
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        do {
            let generateStep = Generate<String, QueryUnderstandingResponse>(
                session: session,
                prompt: { Prompt($0) }
            )
            let response = try await generateStep.run(prompt)

            if verbose {
                printFlush("┌─── LLM OUTPUT (QueryUnderstanding) ───")
                printFlush("subject: \(response.subject)")
                printFlush("reasoning: \(response.reasoning)")
                printFlush("└─── END LLM OUTPUT ───")
                printFlush("")
            }

            let subject = response.subject.trimmingCharacters(in: .whitespacesAndNewlines)

            if subject.isEmpty {
                printFlush("⚠️ LLM returned empty subject, using query as fallback")
                return QueryContext.fallback(query: query)
            }

            return QueryContext(query: query, subject: subject, reasoning: response.reasoning)
        } catch {
            printFlush("⚠️ Query understanding failed: \(error), using query as fallback")
            return QueryContext.fallback(query: query)
        }
    }
}
