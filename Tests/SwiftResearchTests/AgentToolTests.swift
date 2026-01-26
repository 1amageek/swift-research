import Testing
import Foundation
import SwiftAgent
@testable import SwiftResearch

#if USE_OTHER_MODELS
import OpenFoundationModels
import OpenFoundationModelsOllama

// MARK: - Simple Calculator Tool for Testing

@Generable
struct CalculatorInput: Sendable {
    @Guide(description: "First number")
    var a: Int
    @Guide(description: "Second number")
    var b: Int
    @Guide(description: "Operation: add, subtract, multiply, divide")
    var operation: String
}

struct CalculatorOutput: Sendable, PromptRepresentable {
    let result: Int
    let expression: String

    var promptRepresentation: Prompt {
        Prompt("Calculated: \(expression)")
    }
}

struct CalculatorTool: Tool {
    typealias Arguments = CalculatorInput
    typealias Output = CalculatorOutput

    static let name = "calculator"
    var name: String { Self.name }

    static let description = "Perform basic arithmetic calculations"
    var description: String { Self.description }

    var parameters: GenerationSchema {
        CalculatorInput.generationSchema
    }

    func call(arguments: CalculatorInput) async throws -> CalculatorOutput {
        let result: Int
        let op: String
        switch arguments.operation.lowercased() {
        case "add", "+":
            result = arguments.a + arguments.b
            op = "+"
        case "subtract", "-":
            result = arguments.a - arguments.b
            op = "-"
        case "multiply", "*":
            result = arguments.a * arguments.b
            op = "*"
        case "divide", "/":
            result = arguments.b != 0 ? arguments.a / arguments.b : 0
            op = "/"
        default:
            result = arguments.a + arguments.b
            op = "+"
        }
        return CalculatorOutput(result: result, expression: "\(arguments.a) \(op) \(arguments.b) = \(result)")
    }
}

/// Tests to verify that AgentSession properly uses tools with OllamaLanguageModel
@Suite("Agent Tool Tests")
struct AgentToolTests {

    // MARK: - Configuration

    static let modelName = "lfm2.5-thinking"
    static let baseURL = URL(string: "http://127.0.0.1:11434")!

    // MARK: - Tests

    @Test("AgentSession should use tools", .timeLimit(.minutes(2)))
    func agentSessionShouldUseTools() async throws {
        let model = createModel()
        let calculator = CalculatorTool()

        print("=== Testing AgentSession with Tools ===")
        print("Model: \(Self.modelName)")

        // Create AgentSession with tool
        let session = AgentSession(
            model: model,
            tools: [calculator]
        ) {
            Instructions("""
            You are a helpful assistant with access to a calculator tool.
            When asked to perform calculations, you MUST use the calculator tool.
            Do not calculate in your head - always use the tool.
            """)
        }

        // Send a request that requires tool use
        let prompt = "What is 15 + 27? Use the calculator tool to find the answer."
        print("Prompt: \(prompt)")

        let response = try await session.send(prompt)

        print("Response: \(response.content)")
        print("Transcript entries: \(session.transcript.count)")

        // Check for tool calls in transcript
        let toolCalls = session.transcript.allToolCalls
        print("Tool calls found: \(toolCalls.count)")
        for toolCall in toolCalls {
            print("  - Tool: \(toolCall.toolName)")
            print("    Arguments: \(toolCall.arguments.jsonString)")
        }

        // Verify tool was called
        #expect(toolCalls.count > 0, "Expected at least one tool call, but got none")
        #expect(toolCalls.contains { $0.toolName == "calculator" }, "Expected calculator tool to be called")

        print("=== Test Complete ===")
    }

    @Test("ResearchAgent should use WebSearch tool", .timeLimit(.minutes(2)))
    func researchAgentShouldUseTools() async throws {
        let model = createModel()

        print("=== Testing ResearchAgent with Tools ===")
        print("Model: \(Self.modelName)")

        let agent = ResearchAgent(
            model: model,
            configuration: .init(maxURLs: 2, verbose: true)
        )

        let result = try await agent.research("Kyoto")

        print("URLs visited: \(result.visitedURLs.count)")
        print("Answer length: \(result.answer.count)")

        // Verify tools were used
        #expect(result.visitedURLs.count > 0, "Expected at least one URL to be visited, but got none")

        print("=== Test Complete ===")
    }

    @Test("Direct LanguageModelSession with tools works", .timeLimit(.minutes(2)))
    func directLanguageModelSessionWithTools() async throws {
        let model = createModel()
        let calculator = CalculatorTool()

        print("=== Testing Direct LanguageModelSession with Tools ===")
        print("Model: \(Self.modelName)")

        // Use LanguageModelSession directly (not AgentSession)
        let session = LanguageModelSession(
            model: model,
            tools: [calculator],
            instructions: """
            You are a helpful assistant with access to a calculator tool.
            When asked to perform calculations, you MUST use the calculator tool.
            """
        )

        let prompt = "Calculate 15 + 27 using the calculator tool."
        print("Prompt: \(prompt)")

        let response = try await session.respond(to: prompt)

        print("Response: \(response.content)")
        print("Transcript entries: \(session.transcript.count)")

        let toolCalls = session.transcript.allToolCalls
        print("Tool calls found: \(toolCalls.count)")
        for toolCall in toolCalls {
            print("  - Tool: \(toolCall.toolName)")
        }

        #expect(toolCalls.count > 0, "Expected at least one tool call")

        print("=== Test Complete ===")
    }

    // MARK: - Helper Methods

    private func createModel() -> OllamaLanguageModel {
        let config = OllamaConfiguration(baseURL: Self.baseURL, timeout: 120)
        return OllamaLanguageModel(configuration: config, modelName: Self.modelName)
    }
}

#endif
