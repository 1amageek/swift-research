import Foundation
import SwiftAgent

/// Input for objective analysis.
public struct ObjectiveAnalysisInput: Sendable {
    /// The research objective from user.
    public let objective: String

    /// Background information from Phase 0 initial search.
    public let backgroundInfo: String?

    /// Whether to enable verbose logging.
    public let verbose: Bool

    public init(
        objective: String,
        backgroundInfo: String? = nil,
        verbose: Bool = false
    ) {
        self.objective = objective
        self.backgroundInfo = backgroundInfo
        self.verbose = verbose
    }
}

/// Phase 1: Objective Analysis Step.
///
/// Analyzes the user's research objective to extract:
/// - Search keywords for web search
/// - Socratic questions for deeper understanding
/// - Success criteria for determining sufficiency
///
/// ## Example
///
/// ```swift
/// // Run within context that provides ModelContext, config, and queryContext
/// let input = ObjectiveAnalysisInput(objective: "What is Swift concurrency?")
/// let analysis = try await ObjectiveAnalysisStep().run(input)
/// ```
public struct ObjectiveAnalysisStep: Step, Sendable {
    public typealias Input = ObjectiveAnalysisInput
    public typealias Output = ObjectiveAnalysis

    @Context var modelContext: ModelContext
    @Context var config: CrawlerConfiguration
    @Context var queryContext: QueryContext

    /// Progress continuation for sending updates.
    private let progressContinuation: AsyncStream<CrawlProgress>.Continuation?

    public init(
        progressContinuation: AsyncStream<CrawlProgress>.Continuation? = nil
    ) {
        self.progressContinuation = progressContinuation
    }

    public func run(_ input: ObjectiveAnalysisInput) async throws -> ObjectiveAnalysis {
        let session = LanguageModelSession(
            model: modelContext.model,
            tools: [],
            instructions: StepInstructions.objectiveAnalysis
        )

        let backgroundSection = input.backgroundInfo.map { info in
            """

            ## 初期検索で判明した情報
            \(info)
            """
        } ?? ""

        let domainSection = config.domainContext.map { context in
            """

            ## Domain Context
            \(context)
            Interpret the query from this domain's perspective and generate relevant keywords.
            """
        } ?? ""

        let prompt = """
        # ユーザーの質問
        \(input.objective)

        # クエリ理解
        主題: \(queryContext.subject)
        理由: \(queryContext.reasoning)
        \(backgroundSection)
        \(domainSection)

        # あなたの任務
        「\(queryContext.subject)」について以下の3つを生成してください。

        ## 1. 検索キーワード（keywords）
        「\(queryContext.subject)」に関する情報を見つけるためのWeb検索キーワードを生成。
        - 英語で記述（固有名詞は元の言語も可）
        - 検索エンジン向けに最適化
        - キーワードを複数生成すること

        ## 2. 具体的な問い（questions）
        「\(queryContext.subject)」について答えるべき問いを生成。
        - 明確化: 用語や範囲は何を意味しているか？
        - 前提検証: 何を前提としているか？
        - 含意探索: 回答から何が導かれるか？

        ## 3. 成功基準（successCriteria）
        「\(queryContext.subject)」の情報収集完了条件を以下の観点で列挙。
        - 事実: 収集すべき具体的データ（数値、日付、名称など）
        - 背景: その事実の理由や原因
        - 含意: 上記の問い（questions）に回答するために必要な情報

        IMPORTANT: JSONオブジェクトのみを出力。説明文やMarkdownは不要。
        """

        if input.verbose {
            printFlush("┌─── LLM INPUT (ObjectiveAnalysis) ───")
            printFlush(prompt)
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        progressContinuation?.yield(.promptSent(phase: "Phase 1: Objective Analysis", prompt: prompt))

        do {
            let generateStep = Generate<String, ObjectiveAnalysisResponse>(
                session: session,
                prompt: { Prompt($0) }
            )
            let response = try await generateStep.run(prompt)

            if input.verbose {
                printFlush("┌─── LLM OUTPUT (ObjectiveAnalysis) ───")
                printFlush("keywords: \(response.keywords)")
                printFlush("questions: \(response.questions)")
                printFlush("successCriteria: \(response.successCriteria)")
                printFlush("└─── END LLM OUTPUT ───")
                printFlush("")
            }

            let rawAnalysis = response

            if rawAnalysis.keywords.isEmpty {
                printFlush("⚠️ LLM returned empty keywords, using fallback")
                return ObjectiveAnalysis.fallback(objective: queryContext.subject)
            }

            let uniqueKeywords = Array(Set(rawAnalysis.keywords)).prefix(5)
            let uniqueQuestions = Array(Set(rawAnalysis.questions)).prefix(5)
            let uniqueCriteria = Array(Set(rawAnalysis.successCriteria))

            return ObjectiveAnalysis(
                keywords: Array(uniqueKeywords),
                questions: Array(uniqueQuestions),
                successCriteria: uniqueCriteria
            )
        } catch {
            printFlush("⚠️ Objective analysis failed: \(error)")
            return ObjectiveAnalysis.fallback(objective: queryContext.subject)
        }
    }
}
