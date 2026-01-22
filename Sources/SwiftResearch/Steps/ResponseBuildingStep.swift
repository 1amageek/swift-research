import Foundation
import SwiftAgent

/// Input for response building.
public struct ResponseBuildingInput: Sendable {
    /// Relevant excerpts from pages.
    public let relevantExcerpts: [CrawlContext.PageExcerpt]

    /// All reviewed contents.
    public let reviewedContents: [ReviewedContent]

    /// The research objective.
    public let objective: String

    /// Socratic questions to answer.
    public let questions: [String]

    /// Success criteria for the research.
    public let successCriteria: [String]

    /// Whether to enable verbose logging.
    public let verbose: Bool

    public init(
        relevantExcerpts: [CrawlContext.PageExcerpt],
        reviewedContents: [ReviewedContent],
        objective: String,
        questions: [String],
        successCriteria: [String],
        verbose: Bool = false
    ) {
        self.relevantExcerpts = relevantExcerpts
        self.reviewedContents = reviewedContents
        self.objective = objective
        self.questions = questions
        self.successCriteria = successCriteria
        self.verbose = verbose
    }
}

/// Phase 5: Response Building Step.
///
/// Builds the final markdown response from collected information.
/// Synthesizes excerpts and reviews into a coherent answer to the research objective.
///
/// Uses `@Session` for implicit session propagation.
///
/// ## Example
///
/// ```swift
/// try await withSession(session) {
///     let input = ResponseBuildingInput(
///         relevantExcerpts: excerpts,
///         reviewedContents: contents,
///         objective: "...",
///         questions: ["..."],
///         successCriteria: ["..."]
///     )
///     let markdown = try await ResponseBuildingStep().run(input)
/// }
/// ```
public struct ResponseBuildingStep: Step, Sendable {
    public typealias Input = ResponseBuildingInput
    public typealias Output = String

    @Session var session: LanguageModelSession
    @Context var config: CrawlerConfiguration

    /// Progress continuation for sending updates.
    private let progressContinuation: AsyncStream<CrawlProgress>.Continuation?

    public init(
        progressContinuation: AsyncStream<CrawlProgress>.Continuation? = nil
    ) {
        self.progressContinuation = progressContinuation
    }

    public func run(_ input: ResponseBuildingInput) async throws -> String {
        let relevantContents = input.reviewedContents.filter { $0.isRelevant }

        guard !relevantContents.isEmpty else {
            return "# \(input.objective)\n\nNo relevant information could be collected."
        }

        // Build context from relevant excerpts (actual page content, not just summaries)
        var contextSection = ""
        for excerpt in input.relevantExcerpts {
            let title = excerpt.title ?? excerpt.url.absoluteString
            contextSection += "### \(title)\n"
            contextSection += "URL: \(excerpt.url.absoluteString)\n\n"
            for excerptText in excerpt.excerpts {
                contextSection += excerptText + "\n\n"
            }
            contextSection += "---\n\n"
        }

        // Fallback to extractedInfo if no excerpts available
        if contextSection.isEmpty {
            contextSection = relevantContents.enumerated().map { index, content in
                "[\(index + 1)] \(content.url.host ?? "unknown"): \(content.extractedInfo)"
            }.joined(separator: "\n")
        }

        let criteriaList = input.successCriteria.map { "- \($0)" }.joined(separator: "\n")

        let questionsSection = input.questions.isEmpty ? "" : """

        ## Questions to Answer
        \(input.questions.map { "- \($0)" }.joined(separator: "\n"))
        """

        let domainSection = config.domainContext.map { context in
            """

            ## Domain Context
            \(context)
            Generate the response from this domain's perspective.
            """
        } ?? ""

        let prompt = """
        # ユーザーの質問
        \(input.objective)
        \(questionsSection)
        \(domainSection)

        # 成功基準
        以下の情報が含まれていること:
        \(criteriaList)

        # 収集した情報
        \(contextSection)

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
        - 参照リストは不要（システムが追加）

        IMPORTANT: JSONオブジェクトのみを出力。説明文やMarkdownコードフェンスは不要。
        """

        if input.verbose {
            printFlush("┌─── LLM INPUT (FinalResponse) ───")
            printFlush("objective: \(input.objective)")
            printFlush("questions: \(input.questions)")
            printFlush("relevantExcerpts: \(input.relevantExcerpts.count) pages")
            printFlush("contextSection: \(contextSection.count) chars")
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        progressContinuation?.yield(.promptSent(phase: "Phase 5: Response Building", prompt: prompt))

        do {
            let generateStep = Generate<String, FinalResponseBuildingResponse>(
                session: session,
                prompt: { Prompt($0) }
            )
            let response = try await generateStep.run(prompt)

            if input.verbose {
                printFlush("┌─── LLM OUTPUT (FinalResponse) ───")
                printFlush("responseMarkdown: \(response.responseMarkdown.count) chars")
                printFlush(response.responseMarkdown.prefix(500))
                printFlush("...")
                printFlush("└─── END LLM OUTPUT ───")
            }

            var responseMarkdown = response.responseMarkdown
            responseMarkdown += "\n\n## 参照ソース\n"
            for content in relevantContents {
                responseMarkdown += "- \(content.url.absoluteString)\n"
            }

            return responseMarkdown
        } catch {
            printFlush("⚠️ Response building failed: \(error)")
            var fallback = "# \(input.objective)\n\n"
            fallback += contextSection
            fallback += "\n\n## 参照ソース\n"
            for content in relevantContents {
                fallback += "- \(content.url.absoluteString)\n"
            }
            return fallback
        }
    }
}
