import Foundation
import ArgumentParser
import SwiftResearch
import SwiftAgent
import AgentTools
import RemarkKit

#if USE_OTHER_MODELS
import OpenFoundationModelsOllama
import OpenFoundationModelsClaude

enum OllamaError: Error, LocalizedError {
    case connectionFailed
    case serverError(Int)
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to Ollama server. Please ensure Ollama is running."
        case .serverError(let code):
            return "Ollama server error (HTTP \(code))"
        case .modelNotFound(let model):
            return """
            Model '\(model)' not found.

            To download the model, run:
              ollama pull \(model)

            To see available models:
              ollama list
            """
        }
    }
}

func validateOllamaModel(baseURL: URL, modelName: String) async throws {
    let tagsURL = baseURL.appendingPathComponent("api/tags")

    let (data, response): (Data, URLResponse)
    do {
        (data, response) = try await URLSession.shared.data(from: tagsURL)
    } catch {
        throw OllamaError.connectionFailed
    }

    guard let httpResponse = response as? HTTPURLResponse else {
        throw OllamaError.connectionFailed
    }

    if httpResponse.statusCode != 200 {
        throw OllamaError.serverError(httpResponse.statusCode)
    }

    struct TagsResponse: Decodable {
        struct Model: Decodable { let name: String }
        let models: [Model]
    }

    let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
    let modelExists = tags.models.contains { $0.name == modelName || $0.name.hasPrefix(modelName + ":") }

    if !modelExists {
        throw OllamaError.modelNotFound(modelName)
    }
}
#endif

@main
struct ResearchCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "research",
        abstract: "LLM-powered autonomous research assistant",
        version: "1.0.0"
    )

    // MARK: - Arguments

    @Argument(help: "The research query")
    var query: String?

    // MARK: - Options

    @Option(name: .long, help: "Maximum URLs to visit")
    var limit: Int = 50

    @Option(name: .long, help: "Output format (text, json)")
    var format: OutputFormat = .text

    @Flag(name: .long, help: "Show full LLM outputs for each phase")
    var verbose: Bool = false

    @Option(name: .long, help: "Log file path")
    var log: String?

    #if USE_OTHER_MODELS
    @Flag(name: .long, help: "Use Claude API")
    var claude: Bool = false

    @Option(name: .long, help: "Ollama model name (ignored if --claude)")
    var model: String = "lfm2.5-thinking"

    @Option(name: .long, help: "Ollama base URL (ignored if --claude)")
    var baseURL: String = "http://127.0.0.1:11434"

    @Option(name: .long, help: "Request timeout in seconds")
    var timeout: Double = 300.0
    #endif

    // MARK: - Test Options

    @Flag(name: .long, help: "Test search step only")
    var testSearch: Bool = false

    @Flag(name: .long, help: "Test fetch step only")
    var testFetch: Bool = false

    // MARK: - Run

    func run() async throws {
        if testSearch {
            try await runTestSearch()
        } else if testFetch {
            try await runTestFetch()
        } else {
            try await runResearch()
        }
    }

    // MARK: - Research

    private func runResearch() async throws {
        let finalQuery: String
        if let q = query, !q.isEmpty {
            finalQuery = q
        } else {
            print("Enter research query:")
            print("> ", terminator: "")
            guard let input = readLine(), !input.isEmpty else {
                print("No query provided")
                throw ExitCode.failure
            }
            finalQuery = input
        }

        #if USE_OTHER_MODELS
        if !claude {
            guard let baseURLParsed = URL(string: baseURL) else {
                print("Invalid base URL: \(baseURL)")
                throw ExitCode.failure
            }
            do {
                try await validateOllamaModel(baseURL: baseURLParsed, modelName: model)
            } catch let error as OllamaError {
                print(error.localizedDescription)
                throw ExitCode.failure
            } catch {
                print("Skipping model validation: \(error.localizedDescription)")
            }
        }
        #endif

        let languageModel = try createModel()
        let configuration = ResearchAgent.Configuration(
            maxURLs: limit,
            blockedDomains: [],
            verbose: verbose
        )

        let researchAgent = ResearchAgent(
            model: languageModel,
            configuration: configuration
        )

        print("Starting research...")
        #if USE_OTHER_MODELS
        if claude {
            print("Model: Claude Sonnet 4.5 (claude-sonnet-4-5-20250929)")
        } else {
            print("Model: Ollama (\(model))")
        }
        #else
        print("Model: Apple FoundationModels")
        #endif
        print("Query: \(finalQuery)")
        print("Max URLs: \(limit)")
        print("")

        do {
            let result = try await researchAgent.research(finalQuery)
            outputResult(result)
        } catch {
            print("Research failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    // MARK: - Output

    private func outputResult(_ result: ResearchAgent.Result) {
        switch format {
        case .text:
            outputTextResult(result)
        case .json:
            outputJSONResult(result)
        }
    }

    private func outputTextResult(_ result: ResearchAgent.Result) {
        print("")
        print("========================================")
        print("Research Results")
        print("========================================")
        print("")
        print("Duration: \(formatDuration(result.duration))")
        print("URLs visited: \(result.visitedURLs.count)")
        print("")
        print("Sources:")
        for url in result.visitedURLs {
            print("  - \(url)")
        }
        print("")
        print("Answer:")
        print("---")
        print(result.answer)
        print("---")
        print("")
        print("========================================")
    }

    private func outputJSONResult(_ result: ResearchAgent.Result) {
        struct JSONOutput: Codable {
            let objective: String
            let answer: String
            let visitedURLs: [String]
            let durationSeconds: Double
        }

        let output = JSONOutput(
            objective: result.objective,
            answer: result.answer,
            visitedURLs: result.visitedURLs,
            durationSeconds: Double(result.duration.components.seconds)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(output),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    // MARK: - Test Search

    private func runTestSearch() async throws {
        guard let keyword = query, !keyword.isEmpty else {
            print("Keyword required for --test-search")
            throw ExitCode.failure
        }

        print("Testing SearchStep")
        print("Keyword: \(keyword)")
        print("")

        let searchStep = SearchStep(
            searchEngine: .duckDuckGo,
            blockedDomains: []
        )

        let urls = try await searchStep.run(KeywordSearchInput(keyword: keyword))

        print("Results (\(urls.count) URLs):")
        for (i, url) in urls.enumerated() {
            print("[\(i + 1)] \(url)")
        }
    }

    // MARK: - Test Fetch

    private func runTestFetch() async throws {
        guard let urlString = query, let parsedURL = URL(string: urlString) else {
            print("Valid URL required for --test-fetch")
            throw ExitCode.failure
        }

        print("Testing Remark Fetch")
        print("URL: \(parsedURL)")
        print("")

        do {
            let remark = try await Remark.fetch(from: parsedURL, method: .interactive, timeout: 15)
            let links = try remark.extractLinks()

            print("Title: \(remark.title)")
            print("Description: \(remark.description.prefix(200))...")
            print("")
            print("Markdown (\(remark.markdown.count) chars):")
            print("---")
            print(String(remark.markdown.prefix(1000)))
            print("...")
            print("---")
            print("")
            print("Links (\(links.count) found):")
            for (i, link) in links.prefix(20).enumerated() {
                print("[\(i + 1)] \(link.text.isEmpty ? "(no text)" : String(link.text.prefix(50)))")
                print("    -> \(link.url)")
            }
        } catch {
            print("Fetch failed: \(error)")
            throw ExitCode.failure
        }
    }

    // MARK: - Helpers

    private func createModel() throws -> any LanguageModel {
        #if USE_OTHER_MODELS
        if claude {
            guard let config = ClaudeConfiguration.fromEnvironment() else {
                print("Error: ANTHROPIC_API_KEY environment variable is not set")
                throw ExitCode.failure
            }
            return ClaudeLanguageModel.sonnet4_5(configuration: config)
        }

        guard let baseURLParsed = URL(string: baseURL) else {
            print("Invalid base URL: \(baseURL)")
            throw ExitCode.failure
        }

        let ollamaConfig = OllamaConfiguration(
            baseURL: baseURLParsed,
            timeout: timeout,
            keepAlive: "10m"
        )
        return OllamaLanguageModel(
            configuration: ollamaConfig,
            modelName: model
        )
        #else
        return SystemLanguageModel()
        #endif
    }
}

// MARK: - Types

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
}

func formatDuration(_ duration: Duration) -> String {
    let seconds = duration.components.seconds
    if seconds < 60 {
        return "\(seconds)s"
    } else {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }
}
