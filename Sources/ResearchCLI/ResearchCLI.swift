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
        subcommands: [Research.self, TestSearch.self, TestFetch.self, TestEvaluation.self],
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

// MARK: - Test Evaluation Command

extension ResearchCLI {
    struct TestEvaluation: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test-evaluation",
            abstract: "Test the evaluation framework with a sample research"
        )

        @Argument(help: "The objective for research and evaluation")
        var objective: String?

        @Option(name: .long, help: "Maximum URLs to visit")
        var limit: Int = 10

        #if USE_OTHER_MODELS
        @Option(name: .long, help: "Ollama model name")
        var model: String = "gpt-oss:20b"

        @Option(name: .long, help: "Ollama base URL")
        var baseURL: String = "http://127.0.0.1:11434"
        #endif

        func run() async throws {
            let finalObjective: String
            if let obj = objective, !obj.isEmpty {
                finalObjective = obj
            } else {
                finalObjective = "What is the current population of Tokyo?"
            }

            print("🧪 Testing Evaluation Framework")
            print("   Objective: \(finalObjective)")
            print("")

            // Step 1: Create persona first (needed for domain context)
            let persona = Persona(
                domain: .technology,
                role: "Researcher",
                expertise: .intermediate,
                informationNeeds: ["Accurate and current information", "Statistical data"],
                constraints: ["Must include sources", "Clear explanation"]
            )

            // Step 2: Run research with domain context
            print("📚 Phase 1: Running Research...")
            print("   Domain context: \(persona.domain.domainDescription)")
            let session = try createSession()

            #if USE_OTHER_MODELS
            let researchConfig = ResearchConfiguration(llmSupportsConcurrency: true)
            #else
            let researchConfig = ResearchConfiguration(llmSupportsConcurrency: false)
            #endif

            let crawlerConfig = CrawlerConfiguration(
                researchConfiguration: researchConfig,
                domainContext: persona.domain.domainDescription
            )

            #if USE_OTHER_MODELS
            let orchestrator = SearchOrchestratorStep(
                session: session,
                configuration: crawlerConfig,
                verbose: false,
                logFileURL: nil
            )
            #else
            let orchestrator = SearchOrchestratorStep(
                session: session,
                sessionFactory: {
                    let model = SystemLanguageModel()
                    return LanguageModelSession(model: model, tools: [], instructions: nil as String?)
                },
                configuration: crawlerConfig,
                verbose: false,
                logFileURL: nil
            )
            #endif

            let query = SearchQuery(objective: finalObjective, maxVisitedURLs: limit)
            let researchResult = try await orchestrator.run(query)

            print("   ✓ Research completed")
            print("   • Pages visited: \(researchResult.statistics.totalPagesVisited)")
            print("   • Response length: \(researchResult.responseMarkdown.count) chars")
            print("")

            // Step 3: Create evaluation task
            print("📋 Phase 2: Creating Evaluation Task...")

            let task = EvaluationTask(
                persona: persona,
                objective: finalObjective,
                requirements: ["Accurate information", "Current data", "Clear explanation"],
                expectedFormat: .report,
                difficulty: .medium,
                requiresRecentInfo: true,
                searchNecessityScore: 0.9
            )
            print("   ✓ Task created")
            print("")

            // Step 3: Run evaluation
            print("🔍 Phase 3: Running Evaluation...")
            print("   [DEBUG] Research output length: \(researchResult.responseMarkdown.count)")
            print("   [DEBUG] Research output preview: \(String(researchResult.responseMarkdown.prefix(200)))...")

            let evalConfig = EvaluationConfiguration(
                maxStatementsToVerify: 3,  // Reduced for testing
                evidencePerStatement: 1,   // Reduced for testing
                runEvaluationsInParallel: false
            )

            print("   [DEBUG] Starting quality evaluation...")

            // Run quality evaluation separately first
            let qualityStep = AdaptiveQualityStep()
                .session(session)

            let qualityInput = QualityEvaluationInput(
                task: task,
                researchOutput: researchResult.responseMarkdown,
                generalWeight: evalConfig.generalDimensionWeight,
                maxTaskSpecificDimensions: evalConfig.maxTaskSpecificDimensions
            )

            print("   [DEBUG] Calling AdaptiveQualityStep.run()...")
            let qualityResult: QualityEvaluationResult
            do {
                qualityResult = try await qualityStep.run(qualityInput)
                print("   [DEBUG] Quality evaluation completed")
                print("   [DEBUG] Quality score: \(qualityResult.normalizedScore)")
                print("   [DEBUG] Summary: \(qualityResult.summary.prefix(100))...")
            } catch {
                print("   [DEBUG] Quality evaluation FAILED: \(error)")
                throw error
            }

            print("   [DEBUG] Starting fact checking...")

            // Run fact checking separately
            let factCheckStep = FactCheckOrchestratorStep()
                .session(session)
                .context(crawlerConfig)

            let factCheckInput = FactCheckInput(
                researchOutput: researchResult.responseMarkdown,
                maxStatements: evalConfig.maxStatementsToVerify,
                evidencePerStatement: evalConfig.evidencePerStatement,
                confidenceThreshold: evalConfig.verificationConfidenceThreshold
            )

            print("   [DEBUG] Calling FactCheckOrchestratorStep.run()...")
            let factCheckResult: FactCheckResult
            do {
                factCheckResult = try await factCheckStep.run(factCheckInput)
                print("   [DEBUG] Fact checking completed")
                print("   [DEBUG] Total statements: \(factCheckResult.totalStatements)")
                print("   [DEBUG] Correct: \(factCheckResult.correctCount)")
            } catch {
                print("   [DEBUG] Fact checking FAILED: \(error)")
                throw error
            }

            // Combine results
            let evalResult = EvaluationResult(
                task: task,
                researchResult: researchResult,
                qualityResult: qualityResult,
                factCheckResult: factCheckResult,
                startedAt: Date(),
                completedAt: Date(),
                qualityWeight: evalConfig.generalDimensionWeight,
                factualWeight: evalConfig.taskSpecificDimensionWeight
            )

            print("   ✓ Evaluation completed")
            print("")

            // Step 4: Display results
            print("═══════════════════════════════════════════")
            print("📊 Evaluation Results")
            print("═══════════════════════════════════════════")
            print("")

            // Overall scores
            print("📈 Scores:")
            print("   • Overall: \(String(format: "%.1f", evalResult.overallScore))/100")
            print("   • Quality: \(String(format: "%.1f", evalResult.qualityScore))/100")
            print("   • Factual Accuracy: \(String(format: "%.1f", evalResult.factualAccuracy))%")
            print("")

            // Quality details with summary (NEW!)
            print("📝 Quality Assessment:")
            if !evalResult.qualityResult.summary.isEmpty {
                print("   Summary: \(evalResult.qualityResult.summary)")
            }
            print("")
            print("   Dimension Scores:")
            for score in evalResult.qualityResult.dimensionScores {
                print("   • \(score.dimension.name): \(score.score)/10")
                if !score.suggestions.isEmpty {
                    print("     Suggestions: \(score.suggestions.first ?? "")")
                }
            }
            print("")

            if !evalResult.qualityResult.strengths.isEmpty {
                print("   Strengths:")
                for strength in evalResult.qualityResult.strengths {
                    print("   ✓ \(strength)")
                }
                print("")
            }

            if !evalResult.qualityResult.weaknesses.isEmpty {
                print("   Weaknesses:")
                for weakness in evalResult.qualityResult.weaknesses {
                    print("   ✗ \(weakness)")
                }
                print("")
            }

            // Fact check details with corrections (NEW!)
            print("🔎 Fact Check Results:")
            print("   • Total statements: \(evalResult.factCheckResult.totalStatements)")
            print("   • Correct: \(evalResult.factCheckResult.correctCount)")
            print("   • Incorrect: \(evalResult.factCheckResult.incorrectCount)")
            print("   • Unknown: \(evalResult.factCheckResult.unknownCount)")
            print("")

            // Display corrections if any (NEW FEATURE!)
            let corrections = evalResult.factCheckResult.errorSummary
            if !corrections.isEmpty {
                print("   ⚠️  Errors with Corrections:")
                for (i, error) in corrections.prefix(3).enumerated() {
                    print("   [\(i + 1)] Statement: \"\(String(error.statement.prefix(60)))...\"")
                    print("       Correction: \"\(String(error.correction.prefix(80)))...\"")
                }
                print("")
            }

            // Display verification details
            print("   Verification Details:")
            for verification in evalResult.factCheckResult.verifications.prefix(5) {
                let emoji = switch verification.verdict {
                case .correct: "✓"
                case .incorrect: "✗"
                case .partiallyCorrect: "⚠"
                case .unknown: "?"
                }
                print("   \(emoji) [\(verification.verdict.rawValue)] \(String(verification.statement.text.prefix(50)))...")
                if let correction = verification.correction {
                    print("     → Correction: \(String(correction.prefix(60)))...")
                }
            }
            print("")

            print("═══════════════════════════════════════════")
            print("✅ Evaluation framework test completed!")
            print("   Duration: \(String(format: "%.1f", evalResult.completedAt.timeIntervalSince(evalResult.startedAt)))s")
        }

        private func createSession() throws -> LanguageModelSession {
            #if USE_OTHER_MODELS
            guard let baseURLParsed = URL(string: baseURL) else {
                print("❌ Invalid base URL: \(baseURL)")
                throw ExitCode.failure
            }

            let ollamaConfig = OllamaConfiguration(
                baseURL: baseURLParsed,
                timeout: 300.0,
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
