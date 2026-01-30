import Testing
import Foundation
@testable import SwiftResearch

#if USE_OTHER_MODELS
import OpenFoundationModels
import OpenFoundationModelsOllama

/// Tests for understanding LLM response tendencies and variance.
///
/// These tests help identify:
/// 1. Common patterns in LLM responses
/// 2. Sources of variance in output quality
/// 3. Areas where Instructions need improvement
@Suite("Prompt Tendency Tests")
struct PromptTendencyTests {

    // MARK: - Configuration

    static let modelName = "lfm2.5-thinking"
    static let baseURL = URL(string: "http://127.0.0.1:11434")!
    static let iterations = 3

    // MARK: - Test Queries

    static let testQueries: [(query: String, domain: String?)] = [
        ("What is the current population of Tokyo?", nil),
        ("What is the current population of Tokyo?", "Software development, AI, hardware"),
        ("How does Swift concurrency work?", "Software development"),
        ("What are the benefits of exercise?", nil),
    ]

    // MARK: - ObjectiveAnalysis Tests

    @Test("ObjectiveAnalysis generates appropriate success criteria")
    func objectiveAnalysisSuccessCriteria() async throws {
        let session = createSession()

        for (query, domain) in Self.testQueries {
            print("\n═══ Query: \(query) ═══")
            print("Domain: \(domain ?? "none")")

            for i in 1...Self.iterations {
                let prompt = buildObjectiveAnalysisPrompt(query: query, domain: domain)

                do {
                    let response = try await session.respond(to: prompt, generating: ObjectiveAnalysisResponse.self)
                    let analysis = response.content

                    print("\n--- Iteration \(i) ---")
                    print("Keywords: \(analysis.keywords)")
                    print("Questions: \(analysis.questions)")
                    print("Success Criteria: \(analysis.successCriteria)")

                    // Analyze criteria quality
                    let criteriaAnalysis = analyzeCriteria(analysis.successCriteria, query: query)
                    print("Criteria Analysis: \(criteriaAnalysis)")
                } catch {
                    print("\n--- Iteration \(i) ---")
                    print("❌ Error: \(error)")
                }
            }
        }
    }

    @Test("ObjectiveAnalysis criteria types distribution")
    func objectiveAnalysisCriteriaTypes() async throws {
        let session = createSession()
        let query = "What is the current population of Tokyo?"

        var allCriteria: [[String]] = []

        for _ in 1...Self.iterations {
            let prompt = buildObjectiveAnalysisPrompt(query: query, domain: nil)

            do {
                let response = try await session.respond(to: prompt, generating: ObjectiveAnalysisResponse.self)
                allCriteria.append(response.content.successCriteria)
            } catch {
                print("⚠️ Iteration failed: \(error)")
            }
        }

        // Analyze distribution
        print("\n═══ Criteria Type Distribution ═══")
        print("Total iterations: \(Self.iterations)")

        var factualCount = 0
        var analyticalCount = 0
        var metaCount = 0
        var totalCriteria = 0

        for criteria in allCriteria {
            for criterion in criteria {
                totalCriteria += 1
                let type = classifyCriterion(criterion)
                switch type {
                case .factual: factualCount += 1
                case .analytical: analyticalCount += 1
                case .meta: metaCount += 1
                }
            }
        }

        print("Factual: \(factualCount) (\(percentage(factualCount, totalCriteria))%)")
        print("Analytical: \(analyticalCount) (\(percentage(analyticalCount, totalCriteria))%)")
        print("Meta/Abstract: \(metaCount) (\(percentage(metaCount, totalCriteria))%)")

        // Expectation: We want more analytical criteria
        #expect(analyticalCount > 0, "Should generate at least some analytical criteria")
    }

    @Test("Domain context influence on keywords")
    func domainContextInfluence() async throws {
        let session = createSession()
        let query = "What is the current population of Tokyo?"

        // Without domain context
        let promptNoDomain = buildObjectiveAnalysisPrompt(query: query, domain: nil)
        let responseNoDomain = try await session.respond(to: promptNoDomain, generating: ObjectiveAnalysisResponse.self)
        let analysisNoDomain = responseNoDomain.content

        // With unrelated domain context
        let promptWithDomain = buildObjectiveAnalysisPrompt(query: query, domain: "Software development, AI, hardware")
        let responseWithDomain = try await session.respond(to: promptWithDomain, generating: ObjectiveAnalysisResponse.self)
        let analysisWithDomain = responseWithDomain.content

        print("\n═══ Domain Context Influence ═══")
        print("Query: \(query)")
        print("\nWithout domain context:")
        print("  Keywords: \(analysisNoDomain.keywords)")
        print("\nWith unrelated domain context (AI/Software):")
        print("  Keywords: \(analysisWithDomain.keywords)")

        // Check for domain leakage
        let hasUnrelatedTerms = analysisWithDomain.keywords.contains { keyword in
            let lower = keyword.lowercased()
            return lower.contains("ai") || lower.contains("software") || lower.contains("hardware")
        }

        if hasUnrelatedTerms {
            print("\n⚠️ WARNING: Domain context leaked into unrelated query keywords")
        }

        #expect(!hasUnrelatedTerms, "Domain context should not leak into unrelated query keywords")
    }

    // MARK: - Response Quality Tests

    @Test("Response building consistency")
    func responseBuildingConsistency() async throws {
        let session = createSession()

        // Create mock input for ResponseBuildingStep
        let objective = "What is the current population of Tokyo?"
        let questions = [
            "What does 'current population' mean?",
            "How is Tokyo's population measured?",
            "What factors affect population?"
        ]
        let successCriteria = [
            "Specific population figure",
            "Data source",
            "Time period"
        ]

        let mockContent = """
            URL: https://example.com
            Title: Tokyo Population
            Extracted Info: Tokyo's population is approximately 14 million in the city proper and 37 million in the greater metropolitan area as of 2024.
            """

        var responseLengths: [Int] = []
        var containsNumbers: [Bool] = []

        for i in 1...Self.iterations {
            let prompt = buildResponsePrompt(
                objective: objective,
                questions: questions,
                successCriteria: successCriteria,
                content: mockContent
            )

            do {
                let response = try await session.respond(to: prompt, generating: FinalResponseResponse.self)
                let markdown = response.content.responseMarkdown

                responseLengths.append(markdown.count)
                containsNumbers.append(markdown.contains(where: { $0.isNumber }))

                print("\n--- Iteration \(i) ---")
                print("Length: \(markdown.count) chars")
                print("Contains numbers: \(containsNumbers.last!)")
                print("Preview: \(String(markdown.prefix(200)))...")
            } catch {
                print("\n--- Iteration \(i) ---")
                print("❌ Error: \(error)")
            }
        }

        // Analyze variance
        guard !responseLengths.isEmpty else {
            Issue.record("All iterations failed")
            return
        }

        let avgLength = responseLengths.reduce(0, +) / responseLengths.count
        let variance = responseLengths.map { Double(($0 - avgLength) * ($0 - avgLength)) }.reduce(0, +) / Double(responseLengths.count)

        print("\n═══ Response Consistency Analysis ═══")
        print("Average length: \(avgLength) chars")
        print("Variance: \(Int(variance))")
        print("Contains numbers: \(containsNumbers.filter { $0 }.count)/\(responseLengths.count)")

        // Responses should consistently contain numbers for this query
        #expect(containsNumbers.allSatisfy { $0 }, "All responses should contain numeric data for population query")
    }

    // MARK: - Helper Functions

    private static func systemInstructions() -> String {
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

    private func createSession() -> LanguageModelSession {
        let config = OllamaConfiguration(baseURL: Self.baseURL, timeout: 300)
        let model = OllamaLanguageModel(configuration: config, modelName: Self.modelName)
        return LanguageModelSession(model: model, tools: [], instructions: Self.systemInstructions())
    }

    private func buildObjectiveAnalysisPrompt(query: String, domain: String?) -> String {
        let domainSection = domain.map { context in
            """

            ## Domain Context
            \(context)
            Interpret the query from this domain's perspective and generate relevant keywords.
            """
        } ?? ""

        return """
        # ユーザーの質問
        \(query)
        \(domainSection)

        # あなたの任務
        以下の3つを生成してください。

        ## 1. 検索キーワード（keywords）
        Web検索で使用するキーワードを生成。
        - 英語で記述
        - 検索エンジン向けに最適化
        - 3〜5個

        ## 2. 具体的な問い（questions）
        質問に回答するために答えるべき問いを3つ生成。
        - 明確化: 質問の用語や範囲は何を意味しているか？
        - 前提検証: 質問が前提としていることは何か？
        - 含意探索: 回答から何が導かれるか？

        ## 3. 成功基準（successCriteria）
        情報収集の完了条件を以下の観点で列挙。
        - 事実: 収集すべき具体的データ（数値、日付、名称など）
        - 背景: その事実の理由や原因
        - 含意: 上記の問い（questions）に回答するために必要な情報

        IMPORTANT: JSONオブジェクトのみを出力。説明文やMarkdownは不要。
        """
    }

    private func buildResponsePrompt(
        objective: String,
        questions: [String],
        successCriteria: [String],
        content: String
    ) -> String {
        let questionsSection = questions.isEmpty ? "" : """

        ## 考慮すべき問い
        \(questions.map { "- \($0)" }.joined(separator: "\n"))
        """

        let criteriaList = successCriteria.map { "- \($0)" }.joined(separator: "\n")

        return """
        # ユーザーの質問
        \(objective)
        \(questionsSection)

        # 成功基準
        以下の情報が含まれていること:
        \(criteriaList)

        # 収集した情報
        \(content)

        # 回答の構成
        以下の構成でMarkdown形式の回答を生成:
        1. 導入: 質問の要点を簡潔に確認
        2. 事実: 収集した具体的データや情報
        3. 分析: 事実の背景や意味の説明
        4. 結論: 質問への直接的な回答

        # 回答のルール
        - 収集した情報に基づいて回答する
        - 具体的な数値やデータを含める
        - 不明な点は正直に記載する

        IMPORTANT: JSONオブジェクトのみを出力。説明文やMarkdownコードフェンスは不要。
        """
    }

    private func analyzeCriteria(_ criteria: [String], query: String) -> String {
        var analysis: [String] = []

        let hasFactual = criteria.contains { c in
            let lower = c.lowercased()
            // English
            let englishFactual = lower.contains("data") || lower.contains("number") || lower.contains("statistic") ||
                   lower.contains("figure") || lower.contains("population") || lower.contains("fact")
            // Japanese
            let japaneseFactual = c.contains("事実") || c.contains("データ") || c.contains("数値") ||
                   c.contains("日付") || c.contains("名称") || c.contains("人口")
            return englishFactual || japaneseFactual
        }

        let hasAnalytical = criteria.contains { c in
            let lower = c.lowercased()
            // English
            let englishAnalytical = lower.contains("reason") || lower.contains("why") || lower.contains("cause") ||
                   lower.contains("background") || lower.contains("factor") || lower.contains("compare") ||
                   lower.contains("context") || lower.contains("understanding") || lower.contains("meaning") ||
                   lower.contains("implication") || lower.contains("impact") || lower.contains("trend")
            // Japanese
            let japaneseAnalytical = c.contains("背景") || c.contains("理由") || c.contains("原因") ||
                   c.contains("含意") || c.contains("意味") || c.contains("影響") || c.contains("文脈")
            return englishAnalytical || japaneseAnalytical
        }

        let hasMeta = criteria.contains { c in
            let lower = c.lowercased()
            // English
            let englishMeta = lower.contains("clarif") || lower.contains("confirm") || lower.contains("ensure") ||
                   lower.contains("keyword") || lower.contains("json") || lower.contains("format")
            // Japanese
            let japaneseMeta = c.contains("確認") || c.contains("形式") || c.contains("フォーマット")
            return englishMeta || japaneseMeta
        }

        if hasFactual { analysis.append("✓ Has factual criteria") }
        else { analysis.append("✗ Missing factual criteria") }

        if hasAnalytical { analysis.append("✓ Has analytical criteria") }
        else { analysis.append("✗ Missing analytical criteria") }

        if hasMeta { analysis.append("⚠️ Has meta/abstract criteria") }

        return analysis.joined(separator: ", ")
    }

    private enum CriterionType {
        case factual
        case analytical
        case meta
    }

    private func classifyCriterion(_ criterion: String) -> CriterionType {
        let lower = criterion.lowercased()

        // Meta/abstract criteria (about the process, not content)
        if lower.contains("clarif") || lower.contains("confirm") || lower.contains("ensure") ||
           lower.contains("keyword") || lower.contains("json") || lower.contains("format") ||
           lower.contains("question") || lower.contains("criteria") {
            return .meta
        }

        // Analytical criteria (about understanding, not just facts)
        // English keywords
        if lower.contains("reason") || lower.contains("why") || lower.contains("cause") ||
           lower.contains("background") || lower.contains("factor") || lower.contains("compare") ||
           lower.contains("implication") || lower.contains("impact") || lower.contains("trend") ||
           lower.contains("context") || lower.contains("understanding") || lower.contains("meaning") {
            return .analytical
        }

        // Japanese keywords for analytical
        if criterion.contains("背景") || criterion.contains("理由") || criterion.contains("原因") ||
           criterion.contains("含意") || criterion.contains("意味") || criterion.contains("影響") ||
           criterion.contains("傾向") || criterion.contains("比較") || criterion.contains("文脈") {
            return .analytical
        }

        // Default to factual
        return .factual
    }

    private func percentage(_ part: Int, _ total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int(Double(part) / Double(total) * 100)
    }
}

// MARK: - Response Types (test-local)

@Generable
struct ObjectiveAnalysisResponse: Sendable {
    @Guide(description: "Keywords for search (English, search engine optimized)")
    let keywords: [String]

    @Guide(description: "Specific questions to answer")
    let questions: [String]

    @Guide(description: "Criteria for determining information sufficiency")
    let successCriteria: [String]
}

@Generable
struct FinalResponseResponse: Sendable {
    @Guide(description: "The final response in Markdown format")
    let responseMarkdown: String
}

#endif
