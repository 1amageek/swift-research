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
        abstract: "LLM-powered objective-driven research assistant",
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

    @Flag(name: .long, help: "Use AgentSession-based research (experimental)")
    var agent: Bool = false

    // MARK: - Run

    func run() async throws {
        if testSearch {
            try await runTestSearch()
        } else if testFetch {
            try await runTestFetch()
        } else if agent {
            try await runAgentResearch()
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

        #if USE_OTHER_MODELS
        let researchConfig = ResearchConfiguration(llmSupportsConcurrency: true)
        #else
        let researchConfig = ResearchConfiguration(llmSupportsConcurrency: false)
        #endif

        let configuration = CrawlerConfiguration(researchConfiguration: researchConfig)

        let logFileURL: URL?
        if let logPath = log {
            logFileURL = URL(fileURLWithPath: logPath)
            try? "".write(to: logFileURL!, atomically: true, encoding: .utf8)
            print("Logging to: \(logPath)")
        } else {
            logFileURL = nil
        }

        let orchestrator = SearchOrchestratorStep(
            model: languageModel,
            configuration: configuration,
            verbose: verbose || (log != nil),
            logFileURL: logFileURL
        )

        let searchQuery = SearchQuery(objective: finalQuery, maxVisitedURLs: limit)

        let result: AggregatedResult
        do {
            result = try await orchestrator.run(searchQuery)
        } catch {
            print("Crawl failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        outputResult(result)
    }

    // MARK: - Agent Research

    private func runAgentResearch() async throws {
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

        print("Starting AgentSession-based research...")
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
            outputAgentResult(result)
        } catch {
            print("Research failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func outputAgentResult(_ result: ResearchAgent.Result) {
        print("")
        print("========================================")
        print("Research Results (Agent Mode)")
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
            let remark = try await Remark.fetch(from: parsedURL, timeout: 15)
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

    private func outputResult(_ result: AggregatedResult) {
        switch format {
        case .text:
            outputTextResult(result)
        case .json:
            outputJSONResult(result)
        }
    }

    private func outputTextResult(_ result: AggregatedResult) {
        print("")
        print("========================================")
        print("Research Results")
        print("========================================")
        print("")
        print("Objective: \(result.objective)")
        print("Keywords: \(result.keywordsUsed.joined(separator: ", "))")
        print("Questions: \(result.questions.joined(separator: " / "))")
        print("Criteria: \(result.successCriteria.joined(separator: " / "))")
        print("")

        print("Statistics:")
        print("  Pages visited: \(result.statistics.totalPagesVisited)")
        print("  Relevant pages: \(result.statistics.relevantPagesFound)")
        print("  Keywords used: \(result.statistics.keywordsUsed)")
        print("  Duration: \(formatDuration(result.statistics.duration))")
        print("")

        if !result.responseMarkdown.isEmpty {
            print("Response:")
            print("---")
            print(result.responseMarkdown)
            print("")
        }

        let topContents = result.reviewedContents.prefix(5)
        if !topContents.isEmpty {
            print("Sources:")
            print("---")
            for content in topContents {
                print("\(content.title ?? content.url.absoluteString)")
                print("  \(content.extractedInfo.prefix(150))...")
            }
        }

        print("")
        print("========================================")
    }

    private func outputJSONResult(_ result: AggregatedResult) {
        struct JSONOutput: Codable {
            let objective: String
            let questions: [String]
            let successCriteria: [String]
            let keywordsUsed: [String]
            let responseMarkdown: String
            let statistics: Stats
            let reviewedContents: [ReviewedContentOutput]

            struct Stats: Codable {
                let totalPagesVisited: Int
                let relevantPagesFound: Int
                let keywordsUsed: Int
                let durationSeconds: Double
            }

            struct ReviewedContentOutput: Codable {
                let url: String
                let title: String?
                let extractedInfo: String
            }
        }

        let output = JSONOutput(
            objective: result.objective,
            questions: result.questions,
            successCriteria: result.successCriteria,
            keywordsUsed: result.keywordsUsed,
            responseMarkdown: result.responseMarkdown,
            statistics: JSONOutput.Stats(
                totalPagesVisited: result.statistics.totalPagesVisited,
                relevantPagesFound: result.statistics.relevantPagesFound,
                keywordsUsed: result.statistics.keywordsUsed,
                durationSeconds: Double(result.statistics.duration.components.seconds)
            ),
            reviewedContents: result.reviewedContents.map { content in
                JSONOutput.ReviewedContentOutput(
                    url: content.url.absoluteString,
                    title: content.title,
                    extractedInfo: content.extractedInfo
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(output),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    static func systemInstructions() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        let currentDateTime = formatter.string(from: Date())
        let timeZone = TimeZone.current.identifier

        return """
        あなたは情報収集エージェントです。ユーザーの質問に根拠を持って回答するための情報を収集・分析します。

        # 現在の日時
        \(currentDateTime) (\(timeZone))
        IMPORTANT: 「現在」「最新」などの時間表現はこの日時を基準に解釈すること

        # 出力規則
        - 常に有効なJSONオブジェクトで応答する（'{'で開始）
        - 配列フィールドはJSON配列として出力（例: "items": ["a", "b"]）
        - 文字列として配列を出力しない（例: "items": "a, b" は不可）
        - Markdownコードフェンスは含めない
        IMPORTANT: メタ的な説明（「JSONで提供しました」「以下が回答です」等）は出力しない

        # 行動規則
        - 事実に基づいて回答する
        - 不明な場合は推測せず、その旨を明記する
        - 質問の背景・理由・含意も考慮する

        # 分析の観点
        情報を収集・分析する際は以下の観点を考慮:
        - 事実: 具体的なデータ（数値、日付、名称）
        - 背景: その事実の理由や原因
        - 含意: それが意味すること、導かれる結論
        """
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
