import Foundation
import SwiftAgent

/// Input for sufficiency check.
public struct SufficiencyCheckInput: Sendable {
    /// The research objective.
    public let objective: String

    /// Current success criteria.
    public let successCriteria: [String]

    /// Reviewed contents collected so far.
    public let reviewedContents: [ReviewedContent]

    /// Number of relevant pages found.
    public let relevantCount: Int

    /// Current search round number.
    public let searchRoundNumber: Int

    /// Number of new relevant pages found this round.
    public let newRelevantThisRound: Int

    /// Whether to enable verbose logging.
    public let verbose: Bool

    public init(
        objective: String,
        successCriteria: [String],
        reviewedContents: [ReviewedContent],
        relevantCount: Int,
        searchRoundNumber: Int,
        newRelevantThisRound: Int,
        verbose: Bool = false
    ) {
        self.objective = objective
        self.successCriteria = successCriteria
        self.reviewedContents = reviewedContents
        self.relevantCount = relevantCount
        self.searchRoundNumber = searchRoundNumber
        self.newRelevantThisRound = newRelevantThisRound
        self.verbose = verbose
    }
}

/// Phase 4: Sufficiency Check Step.
///
/// Evaluates whether sufficient information has been collected to answer the research objective.
/// Uses Self-reflection to analyze information completeness and identify gaps.
///
/// Uses `@Session` for implicit session propagation.
///
/// ## Example
///
/// ```swift
/// try await withSession(session) {
///     let input = SufficiencyCheckInput(
///         objective: "...",
///         successCriteria: ["..."],
///         reviewedContents: contents,
///         relevantCount: 5,
///         searchRoundNumber: 1,
///         newRelevantThisRound: 3
///     )
///     let result = try await SufficiencyCheckStep().run(input)
/// }
/// ```
public struct SufficiencyCheckStep: Step, Sendable {
    public typealias Input = SufficiencyCheckInput
    public typealias Output = SufficiencyResult

    @Session var session: LanguageModelSession
    @Context var config: CrawlerConfiguration

    /// Progress continuation for sending updates.
    private let progressContinuation: AsyncStream<CrawlProgress>.Continuation?

    public init(
        progressContinuation: AsyncStream<CrawlProgress>.Continuation? = nil
    ) {
        self.progressContinuation = progressContinuation
    }

    public func run(_ input: SufficiencyCheckInput) async throws -> SufficiencyResult {
        guard !input.reviewedContents.isEmpty else {
            return SufficiencyResult.insufficient(reason: "まだ関連情報が収集できていません")
        }

        let collectedInfo = input.reviewedContents
            .filter { $0.isRelevant }
            .prefix(10)
            .map { content in
                "【\(content.url.host ?? "unknown")】\(content.extractedInfo)"
            }
            .joined(separator: "\n")

        let criteriaList = input.successCriteria
            .map { "- \($0)" }
            .joined(separator: "\n")

        let domainSection = config.domainContext.map { context in
            """

            ## Domain Context
            \(context)
            Evaluate sufficiency from this domain's perspective.
            """
        } ?? ""

        let prompt = """
        あなたは情報充足度を判断するエージェントです。
        収集した情報の完全性を分析し、情報ギャップを特定してください。

        ## 目的
        \(input.objective)
        \(domainSection)

        ## 現在の成功基準
        \(criteriaList)

        ## 検索履歴
        - 検索ラウンド: \(input.searchRoundNumber)回目
        - このラウンドで見つかった新規関連ページ: \(input.newRelevantThisRound)件
        - 累計関連ページ: \(input.relevantCount)件

        ## これまでに収集した情報
        \(collectedInfo)

        ## あなたの任務

        ### 1. Self-reflection: 情報の完全性分析
        各成功基準について、収集した情報がどの程度その基準を満たしているかを評価してください。
        - 完全に満たしている
        - 部分的に満たしている（何が不足か明記）
        - まだ情報がない

        ### 2. isSufficient（十分か？）
        全ての成功基準が満たされていればtrue。

        ### 3. shouldGiveUp（諦めるか？）
        - このラウンドで新規関連ページが0件
        - 複数ラウンド経過しても情報が増えていない

        ### 4. additionalKeywords（追加キーワード）
        情報ギャップを埋めるための具体的な検索キーワード（最大2個）。
        前回の検索結果から得た洞察を活用して、より精密なクエリを構築。

        ### 5. reasonMarkdown（判断理由）
        各成功基準の達成状況と、残っている情報ギャップを簡潔に記述。

        ### 6. successCriteria（精緻化された成功基準）
        収集した情報により成功基準を事後更新してください。
        - 曖昧だった基準は収集した情報を基に具体化
        - 新たな情報から必要と判明した基準は追加
        - 変更がなければ現在の基準をそのまま返す
        """

        if input.verbose {
            printFlush("┌─── LLM INPUT (SufficiencyCheck) ───")
            printFlush("objective: \(input.objective)")
            printFlush("successCriteria: \(input.successCriteria)")
            printFlush("searchRound: \(input.searchRoundNumber), newRelevantThisRound: \(input.newRelevantThisRound)")
            printFlush("collectedInfo: \(input.reviewedContents.count) items")
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        progressContinuation?.yield(.promptSent(phase: "Phase 4: Sufficiency Check", prompt: prompt))

        do {
            let response = try await session.respond(generating: SufficiencyCheckResponse.self) {
                Prompt(prompt)
            }

            if input.verbose {
                printFlush("┌─── LLM OUTPUT (SufficiencyCheck) ───")
                printFlush("isSufficient: \(response.content.isSufficient)")
                printFlush("shouldGiveUp: \(response.content.shouldGiveUp)")
                printFlush("additionalKeywords: \(response.content.additionalKeywords)")
                printFlush("reasonMarkdown: \(response.content.reasonMarkdown.prefix(200))...")
                printFlush("└─── END LLM OUTPUT ───")
            }

            return SufficiencyResult(from: response.content)
        } catch {
            printFlush("⚠️ Sufficiency check failed: \(error)")
            return SufficiencyResult.insufficient(reason: "充足度チェック失敗")
        }
    }
}
