import Foundation
import ArgumentParser
import SwiftResearch
import RemarkKit

#if USE_OTHER_MODELS
import OpenFoundationModelsOllama
#endif

@main
struct ResearchCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "research-cli",
        abstract: "LLM-powered objective-driven research assistant",
        version: "1.0.0",
        subcommands: [Research.self, TestSearch.self, TestFetch.self],
        defaultSubcommand: Research.self
    )
}

// MARK: - Test Commands for Individual Steps

extension ResearchCLI {
    /// Test SearchStep: keyword → URL list
    struct TestSearch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test-search",
            abstract: "Test SearchStep: keyword → URLs"
        )

        @Argument(help: "Search keyword")
        var keyword: String

        func run() async throws {
            print("🔍 Testing SearchStep")
            print("   Keyword: \(keyword)")
            print("")

            let searchStep = SearchStep(
                searchEngine: .duckDuckGo,
                blockedDomains: []
            )

            let urls = try await searchStep.run(KeywordSearchInput(keyword: keyword))

            print("📋 Results (\(urls.count) URLs):")
            for (i, url) in urls.enumerated() {
                print("   [\(i + 1)] \(url)")
            }
        }
    }

    /// Test Remark fetch: URL → Markdown
    struct TestFetch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test-fetch",
            abstract: "Test Remark fetch: URL → Markdown + Links"
        )

        @Argument(help: "URL to fetch")
        var url: String

        func run() async throws {
            guard let parsedURL = URL(string: url) else {
                print("❌ Invalid URL: \(url)")
                throw ExitCode.failure
            }

            print("📄 Testing Remark Fetch")
            print("   URL: \(parsedURL)")
            print("")

            do {
                let remark = try await Remark.fetch(from: parsedURL)
                let links = try remark.extractLinks()

                print("📝 Title: \(remark.title)")
                print("📝 Description: \(remark.description.prefix(200))...")
                print("")
                print("📄 Markdown (\(remark.markdown.count) chars):")
                print("───────────────────────────────────────────")
                print(String(remark.markdown.prefix(1000)))
                print("...")
                print("───────────────────────────────────────────")
                print("")
                print("🔗 Links (\(links.count) found):")
                for (i, link) in links.prefix(20).enumerated() {
                    print("   [\(i + 1)] \(link.text.isEmpty ? "(no text)" : String(link.text.prefix(50)))")
                    print("       → \(link.url)")
                }
            } catch {
                print("❌ Fetch failed: \(error)")
                throw ExitCode.failure
            }
        }
    }

}

// MARK: - Research Command

extension ResearchCLI {
    struct Research: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Research based on an objective"
        )

        @Argument(help: "The objective for information gathering (optional, will prompt if not provided)")
        var objective: String?

        @Option(name: .long, help: "Maximum URLs to visit (safety limit)")
        var limit: Int = 50

        #if USE_OTHER_MODELS
        @Option(name: .long, help: "Ollama model name")
        var model: String = "gpt-oss:20b"

        @Option(name: .long, help: "Ollama base URL")
        var baseURL: String = "http://127.0.0.1:11434"

        @Option(name: .long, help: "Request timeout in seconds")
        var timeout: Double = 300.0
        #endif

        @Option(name: .long, help: "Output format (text, json)")
        var format: OutputFormat = .text

        @Flag(name: .long, help: "Show full LLM outputs for each phase")
        var verbose: Bool = false

        @Option(name: .long, help: "Log file path (verbose output will be written to this file)")
        var log: String?

        func run() async throws {
            // Get objective (prompt if not provided)
            let finalObjective: String
            if let obj = objective, !obj.isEmpty {
                finalObjective = obj
            } else {
                print("🎯 Enter research objective:")
                print("> ", terminator: "")
                guard let input = readLine(), !input.isEmpty else {
                    print("❌ No objective provided")
                    throw ExitCode.failure
                }
                finalObjective = input
            }

            // Create language model session
            let session = try createSession()

            // Configure based on LLM type
            #if USE_OTHER_MODELS
            // API-based models support concurrent requests
            let researchConfig = ResearchConfiguration(llmSupportsConcurrency: true)
            #else
            // SystemLanguageModel does NOT support concurrent requests
            let researchConfig = ResearchConfiguration(llmSupportsConcurrency: false)
            #endif

            let configuration = CrawlerConfiguration(researchConfiguration: researchConfig)

            // Set up log file
            let logFileURL: URL?
            if let logPath = log {
                logFileURL = URL(fileURLWithPath: logPath)
                try? "".write(to: logFileURL!, atomically: true, encoding: .utf8)
                print("📝 Logging to: \(logPath)")
            } else {
                logFileURL = nil
            }

            #if USE_OTHER_MODELS
            let orchestrator = SearchOrchestratorStep(
                session: session,
                configuration: configuration,
                verbose: verbose || (log != nil),
                logFileURL: logFileURL
            )
            #else
            // Provide session factory for non-concurrent LLM
            let orchestrator = SearchOrchestratorStep(
                session: session,
                sessionFactory: {
                    let model = SystemLanguageModel()
                    return LanguageModelSession(model: model, tools: [], instructions: nil as String?)
                },
                configuration: configuration,
                verbose: verbose || (log != nil),
                logFileURL: logFileURL
            )
            #endif

            let query = SearchQuery(objective: finalObjective, maxVisitedURLs: limit)

            let result: AggregatedResult
            do {
                result = try await orchestrator.run(query)
            } catch {
                print("❌ Crawl failed: \(error.localizedDescription)")
                throw ExitCode.failure
            }

            outputAggregatedResult(result, format: format)
        }

        private func createSession() throws -> LanguageModelSession {
            #if USE_OTHER_MODELS
            guard let baseURLParsed = URL(string: baseURL) else {
                print("❌ Invalid base URL: \(baseURL)")
                throw ExitCode.failure
            }

            let ollamaConfig = OllamaConfiguration(
                baseURL: baseURLParsed,
                timeout: timeout,
                keepAlive: "10m"
            )
            let ollamaModel = OllamaLanguageModel(
                configuration: ollamaConfig,
                modelName: model
            )
            return LanguageModelSession(model: ollamaModel, tools: [], instructions: nil as String?)
            #else
            let model = SystemLanguageModel()
            return LanguageModelSession(model: model, tools: [], instructions: nil as String?)
            #endif
        }
    }
}


// MARK: - Output Format

enum OutputFormat: String, ExpressibleByArgument {
    case text
    case json
}

// MARK: - Output Helpers for AggregatedResult

func outputAggregatedResult(_ result: AggregatedResult, format: OutputFormat) {
    switch format {
    case .text:
        outputTextAggregatedResult(result)
    case .json:
        outputJSONAggregatedResult(result)
    }
}

func outputTextAggregatedResult(_ result: AggregatedResult) {
    print("")
    print("═══════════════════════════════════════════")
    print("📊 Aggregated Crawl Results")
    print("═══════════════════════════════════════════")
    print("")
    print("📌 Objective: \(result.objective)")
    print("🔑 Keywords: \(result.keywordsUsed.joined(separator: ", "))")
    print("❓ Questions: \(result.questions.joined(separator: " / "))")
    print("✓ Criteria: \(result.successCriteria.joined(separator: " / "))")
    print("")

    print("📈 Statistics:")
    print("   • Pages visited: \(result.statistics.totalPagesVisited)")
    print("   • Relevant pages: \(result.statistics.relevantPagesFound)")
    print("   • Keywords used: \(result.statistics.keywordsUsed)")
    print("   • Duration: \(formatDuration(result.statistics.duration))")
    print("")

    // Display final response
    if !result.responseMarkdown.isEmpty {
        print("📝 Response:")
        print("───────────────────────────────────────────")
        print(result.responseMarkdown)
        print("")
    }

    // Display reviewed contents
    let topContents = result.reviewedContents.prefix(5)

    if !topContents.isEmpty {
        print("🔍 Sources:")
        print("───────────────────────────────────────────")
        for content in topContents {
            print("📄 \(content.title ?? content.url.absoluteString)")
            print("   \(content.extractedInfo.prefix(150))...")
        }
    }

    print("")
    print("═══════════════════════════════════════════")
}

func outputJSONAggregatedResult(_ result: AggregatedResult) {
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
