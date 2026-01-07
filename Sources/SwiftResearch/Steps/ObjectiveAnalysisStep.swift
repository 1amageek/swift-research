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
/// Uses `@Session` for implicit session propagation.
///
/// ## Example
///
/// ```swift
/// try await withSession(session) {
///     let input = ObjectiveAnalysisInput(
///         objective: "What is Swift concurrency?",
///         backgroundInfo: nil
///     )
///     let analysis = try await ObjectiveAnalysisStep().run(input)
/// }
/// ```
public struct ObjectiveAnalysisStep: Step, Sendable {
    public typealias Input = ObjectiveAnalysisInput
    public typealias Output = ObjectiveAnalysis

    @Session var session: LanguageModelSession

    /// Progress continuation for sending updates.
    private let progressContinuation: AsyncStream<CrawlProgress>.Continuation?

    public init(
        progressContinuation: AsyncStream<CrawlProgress>.Continuation? = nil
    ) {
        self.progressContinuation = progressContinuation
    }

    public func run(_ input: ObjectiveAnalysisInput) async throws -> ObjectiveAnalysis {
        let backgroundSection = input.backgroundInfo.map { info in
            """

            ## 初期検索で判明した情報
            \(info)
            """
        } ?? ""

        let prompt = """
        あなたは情報収集エージェントです。

        ## 目的
        ユーザーの質問に根拠を持って答えること

        ## ユーザーの質問
        \(input.objective)
        \(backgroundSection)

        ## あなたの任務

        ### 1. 検索キーワード（keywords）
        目的を達成するための検索キーワードを生成。
        - 英語で記述
        - 検索エンジン向け

        ### 2. 具体的な問い（questions）
        目的を達成するために答えるべき具体的な問いを3つ生成。
        - 明確化: 何を意味しているか？
        - 前提検証: 何を前提としているか？
        - 含意探索: 何が導かれるか？

        ### 3. 成功基準（successCriteria）
        情報収集が十分と判断するための具体的な条件を詳細にリスト化。
        - 目的を達成するために必要な情報項目を全て列挙
        - 具体的な属性名を明記する

        """

        if input.verbose {
            printFlush("┌─── LLM INPUT (ObjectiveAnalysis) ───")
            printFlush(prompt)
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        progressContinuation?.yield(.promptSent(phase: "Phase 1: Objective Analysis", prompt: prompt))

        do {
            let response = try await session.respond(generating: ObjectiveAnalysisResponse.self) {
                Prompt(prompt)
            }

            if input.verbose {
                printFlush("┌─── LLM OUTPUT (ObjectiveAnalysis) ───")
                printFlush("keywords: \(response.content.keywords)")
                printFlush("questions: \(response.content.questions)")
                printFlush("successCriteria: \(response.content.successCriteria)")
                printFlush("└─── END LLM OUTPUT ───")
                printFlush("")
            }

            let rawAnalysis = response.content

            if rawAnalysis.keywords.isEmpty {
                printFlush("⚠️ LLM returned empty keywords, using fallback")
                return ObjectiveAnalysis.fallback(objective: input.objective)
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
            return ObjectiveAnalysis.fallback(objective: input.objective)
        }
    }
}
