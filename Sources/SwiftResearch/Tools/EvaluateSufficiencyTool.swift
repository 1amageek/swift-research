import Foundation
import SwiftAgent

/// A tool for evaluating whether collected information is sufficient.
///
/// Uses a separate LLM session to objectively evaluate the completeness
/// of collected information against the research objective.
public struct EvaluateSufficiencyTool: Tool, Sendable {
    public typealias Arguments = EvaluateSufficiencyInput
    public typealias Output = EvaluateSufficiencyOutput

    public static let name = "EvaluateSufficiency"
    public var name: String { Self.name }

    public static let description = """
    Evaluate whether the collected information is sufficient to answer the user's question.
    Call this periodically to check if you have gathered enough information.
    Returns an assessment of completeness and recommendations for next steps.
    """

    public var description: String { Self.description }

    public var parameters: GenerationSchema {
        EvaluateSufficiencyInput.generationSchema
    }

    private let model: any LanguageModel

    public init(model: some LanguageModel) {
        self.model = model
    }

    public func call(arguments: EvaluateSufficiencyInput) async throws -> EvaluateSufficiencyOutput {
        // Create a separate session for objective evaluation
        let evaluationSession = LanguageModelSession(
            model: model,
            tools: [],
            instructions: Self.evaluationInstructions
        )

        let prompt = """
        ## Research Objective
        \(arguments.objective)

        ## Collected Information Summary
        \(arguments.collectedInfo)

        ## Progress
        - URLs visited: \(arguments.visitedCount) / \(arguments.maxURLs)

        ## Your Task
        Evaluate whether the collected information is sufficient to comprehensively answer the research objective.

        Consider:
        1. Does the information cover all key aspects of the question?
        2. Is the information from reliable sources?
        3. Are there any obvious gaps or missing perspectives?
        4. Is there enough depth to provide a thorough answer?

        Respond with your evaluation.
        """

        let response = try await evaluationSession.respond(
            generating: EvaluateSufficiencyResponse.self
        ) {
            Prompt(prompt)
        }

        return EvaluateSufficiencyOutput(
            isSufficient: response.content.isSufficient,
            gaps: response.content.gaps,
            recommendation: response.content.recommendation,
            reasoning: response.content.reasoning
        )
    }

    private static let evaluationInstructions = """
    You are an objective research quality evaluator.
    Your role is to assess whether collected information is sufficient to answer a research question.

    Be critical but fair:
    - If key information is missing, mark as insufficient
    - If the information covers the main aspects adequately, mark as sufficient
    - Provide specific, actionable recommendations for improvement
    - Consider the URL limit when making recommendations

    Always respond in the required JSON format.
    """
}

// MARK: - Input/Output Types

/// Input for sufficiency evaluation.
@Generable
public struct EvaluateSufficiencyInput: Sendable {
    @Guide(description: "The user's research question or objective")
    public let objective: String

    @Guide(description: "Summary of information collected so far")
    public let collectedInfo: String

    @Guide(description: "Number of URLs visited")
    public let visitedCount: Int

    @Guide(description: "Maximum number of URLs allowed to visit")
    public let maxURLs: Int
}

/// Internal response type for LLM generation.
@Generable
struct EvaluateSufficiencyResponse: Sendable {
    @Guide(description: "Whether the collected information is sufficient to answer the objective")
    let isSufficient: Bool

    @Guide(description: "List of information gaps or missing aspects")
    let gaps: [String]

    @Guide(description: "Recommended next action (e.g., 'search for X', 'fetch page about Y', 'sufficient to answer')")
    let recommendation: String

    @Guide(description: "Reasoning for the evaluation")
    let reasoning: String
}

/// Output for sufficiency evaluation.
public struct EvaluateSufficiencyOutput: Sendable {
    /// Whether the collected information is sufficient.
    public let isSufficient: Bool

    /// List of information gaps if not sufficient.
    public let gaps: [String]

    /// Recommended next action.
    public let recommendation: String

    /// Reasoning for the evaluation.
    public let reasoning: String

    public init(isSufficient: Bool, gaps: [String], recommendation: String, reasoning: String) {
        self.isSufficient = isSufficient
        self.gaps = gaps
        self.recommendation = recommendation
        self.reasoning = reasoning
    }
}

extension EvaluateSufficiencyOutput: CustomStringConvertible {
    public var description: String {
        let status = isSufficient ? "SUFFICIENT" : "INSUFFICIENT"
        var output = """
        EvaluateSufficiency [\(status)]

        Reasoning: \(reasoning)
        """

        if !gaps.isEmpty {
            output += "\n\nGaps:"
            for gap in gaps {
                output += "\n- \(gap)"
            }
        }

        output += "\n\nRecommendation: \(recommendation)"

        return output
    }
}

extension EvaluateSufficiencyOutput: PromptRepresentable {
    public var promptRepresentation: Prompt {
        Prompt(description)
    }
}
