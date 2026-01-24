import Testing
import Foundation
@testable import SwiftResearch

#if USE_OTHER_MODELS
import OpenFoundationModels
import OpenFoundationModelsOllama

/// Benchmark tests for the evaluation framework.
/// Runs full research + quality evaluation + fact checking pipeline.
@Suite("Evaluation Benchmark Tests")
struct EvaluationBenchmarkTests {

    // MARK: - Configuration

    static let modelName = "lfm2.5-thinking"
    static let baseURL = URL(string: "http://127.0.0.1:11434")!
    static let maxURLs = 10

    // MARK: - Benchmark Tests

    @Test("Full evaluation pipeline benchmark", .timeLimit(.minutes(10)))
    func fullEvaluationBenchmark() async throws {
        let objective = "What is the current population of Tokyo?"

        print("Testing Evaluation Framework")
        print("   Objective: \(objective)")
        print("")

        // Step 1: Create persona
        let persona = Persona(
            domain: .technology,
            role: "Researcher",
            expertise: .intermediate,
            informationNeeds: ["Accurate and current information", "Statistical data"],
            constraints: ["Must include sources", "Clear explanation"]
        )

        // Step 2: Run research
        print("Phase 1: Running Research...")
        print("   Domain context: \(persona.domain.domainDescription)")

        let session = createSession()

        let researchConfig = ResearchConfiguration(llmSupportsConcurrency: true)
        let crawlerConfig = CrawlerConfiguration(
            researchConfiguration: researchConfig,
            domainContext: persona.domain.domainDescription
        )

        let orchestrator = SearchOrchestratorStep(
            model: createModel(),
            configuration: crawlerConfig,
            verbose: false,
            logFileURL: nil
        )

        let query = SearchQuery(objective: objective, maxVisitedURLs: Self.maxURLs)
        let researchResult = try await orchestrator.run(query)

        print("   Research completed")
        print("   Pages visited: \(researchResult.statistics.totalPagesVisited)")
        print("   Response length: \(researchResult.responseMarkdown.count) chars")
        print("")

        #expect(researchResult.responseMarkdown.count > 0, "Research should produce output")

        // Step 3: Create evaluation task
        print("Phase 2: Creating Evaluation Task...")

        let task = EvaluationTask(
            persona: persona,
            objective: objective,
            requirements: ["Accurate information", "Current data", "Clear explanation"],
            expectedFormat: .report,
            difficulty: .medium,
            requiresRecentInfo: true,
            searchNecessityScore: 0.9
        )
        print("   Task created")
        print("")

        // Step 4: Run evaluation
        print("Phase 3: Running Evaluation...")

        let evalConfig = EvaluationConfiguration(
            maxStatementsToVerify: 3,
            evidencePerStatement: 1,
            runEvaluationsInParallel: false
        )

        // Quality evaluation
        print("   Running quality evaluation...")
        let qualityStep = AdaptiveQualityStep()
            .session(session)

        let qualityInput = QualityEvaluationInput(
            task: task,
            researchOutput: researchResult.responseMarkdown,
            generalWeight: evalConfig.generalDimensionWeight,
            maxTaskSpecificDimensions: evalConfig.maxTaskSpecificDimensions
        )

        let qualityResult = try await qualityStep.run(qualityInput)
        print("   Quality score: \(String(format: "%.1f", qualityResult.normalizedScore))")

        // Fact checking
        print("   Running fact checking...")
        let factCheckStep = FactCheckOrchestratorStep()
            .session(session)
            .context(crawlerConfig)

        let factCheckInput = FactCheckInput(
            researchOutput: researchResult.responseMarkdown,
            maxStatements: evalConfig.maxStatementsToVerify,
            evidencePerStatement: evalConfig.evidencePerStatement,
            confidenceThreshold: evalConfig.verificationConfidenceThreshold
        )

        let factCheckResult = try await factCheckStep.run(factCheckInput)
        print("   Statements verified: \(factCheckResult.totalStatements)")
        print("")

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

        // Display results
        print("═══════════════════════════════════════════")
        print("Evaluation Results")
        print("═══════════════════════════════════════════")
        print("")

        print("Scores:")
        print("   Overall: \(String(format: "%.1f", evalResult.overallScore))/100")
        print("   Quality: \(String(format: "%.1f", evalResult.qualityScore))/100")
        print("   Factual Accuracy: \(String(format: "%.1f", evalResult.factualAccuracy))%")
        print("")

        print("Quality Assessment:")
        if !evalResult.qualityResult.summary.isEmpty {
            print("   Summary: \(evalResult.qualityResult.summary)")
        }
        print("")
        print("   Dimension Scores:")
        for score in evalResult.qualityResult.dimensionScores {
            print("   \(score.dimension.name): \(score.score)/10")
        }
        print("")

        if !evalResult.qualityResult.strengths.isEmpty {
            print("   Strengths:")
            for strength in evalResult.qualityResult.strengths {
                print("   + \(strength)")
            }
            print("")
        }

        if !evalResult.qualityResult.weaknesses.isEmpty {
            print("   Weaknesses:")
            for weakness in evalResult.qualityResult.weaknesses {
                print("   - \(weakness)")
            }
            print("")
        }

        print("Fact Check Results:")
        print("   Total statements: \(evalResult.factCheckResult.totalStatements)")
        print("   Correct: \(evalResult.factCheckResult.correctCount)")
        print("   Incorrect: \(evalResult.factCheckResult.incorrectCount)")
        print("   Unknown: \(evalResult.factCheckResult.unknownCount)")
        print("")

        let corrections = evalResult.factCheckResult.errorSummary
        if !corrections.isEmpty {
            print("   Errors with Corrections:")
            for (i, error) in corrections.prefix(3).enumerated() {
                print("   [\(i + 1)] \"\(String(error.statement.prefix(60)))...\"")
                print("       -> \"\(String(error.correction.prefix(80)))...\"")
            }
            print("")
        }

        print("   Verification Details:")
        for verification in evalResult.factCheckResult.verifications.prefix(5) {
            let emoji = switch verification.verdict {
            case .correct: "+"
            case .incorrect: "x"
            case .partiallyCorrect: "~"
            case .unknown: "?"
            case .errorOccurred: "!"
            }
            print("   \(emoji) [\(verification.verdict.rawValue)] \(String(verification.statement.text.prefix(50)))...")
        }
        print("")

        print("═══════════════════════════════════════════")

        // Assertions
        #expect(evalResult.overallScore >= 0, "Overall score should be non-negative")
        #expect(evalResult.qualityScore >= 0, "Quality score should be non-negative")
        #expect(evalResult.factualAccuracy >= 0, "Factual accuracy should be non-negative")

        // Baseline expectations from docs/evaluation-experiments.md
        #expect(evalResult.overallScore >= 70, "Overall score should meet baseline (>=70)")
        #expect(evalResult.qualityScore >= 60, "Quality score should meet baseline (>=60)")
    }

    @Test("Quality evaluation only", .timeLimit(.minutes(5)))
    func qualityEvaluationOnly() async throws {
        let objective = "What are the benefits of regular exercise?"
        let mockResearchOutput = """
        # Benefits of Regular Exercise

        Regular exercise provides numerous health benefits:

        ## Physical Health
        - Improves cardiovascular health
        - Helps maintain healthy weight
        - Strengthens muscles and bones
        - Reduces risk of chronic diseases

        ## Mental Health
        - Reduces stress and anxiety
        - Improves mood and emotional well-being
        - Enhances cognitive function
        - Promotes better sleep

        ## Sources
        - WHO Physical Activity Guidelines
        - CDC Exercise Recommendations
        """

        let persona = Persona(
            domain: .medicine,
            role: "Health Researcher",
            expertise: .intermediate,
            informationNeeds: ["Health benefits", "Scientific evidence"],
            constraints: ["Evidence-based information"]
        )

        let task = EvaluationTask(
            persona: persona,
            objective: objective,
            requirements: ["Comprehensive coverage", "Clear structure"],
            expectedFormat: .report,
            difficulty: .easy,
            requiresRecentInfo: false,
            searchNecessityScore: 0.5
        )

        let session = createSession()
        let qualityStep = AdaptiveQualityStep().session(session)

        let input = QualityEvaluationInput(
            task: task,
            researchOutput: mockResearchOutput,
            generalWeight: 0.6,
            maxTaskSpecificDimensions: 3
        )

        let result = try await qualityStep.run(input)

        print("Quality Evaluation Results:")
        print("   Score: \(String(format: "%.1f", result.normalizedScore))/100")
        print("   Summary: \(result.summary)")
        print("")
        print("   Dimensions:")
        for score in result.dimensionScores {
            print("   \(score.dimension.name): \(score.score)/10")
        }

        #expect(result.normalizedScore > 0, "Should produce a quality score")
        #expect(!result.dimensionScores.isEmpty, "Should have dimension scores")
    }

    // MARK: - Helpers

    private func createModel() -> OllamaLanguageModel {
        let config = OllamaConfiguration(baseURL: Self.baseURL, timeout: 300)
        return OllamaLanguageModel(configuration: config, modelName: Self.modelName)
    }

    private func createSession() -> LanguageModelSession {
        let model = createModel()
        return LanguageModelSession(model: model, tools: [], instructions: systemInstructions())
    }

    private func systemInstructions() -> String {
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

#endif
