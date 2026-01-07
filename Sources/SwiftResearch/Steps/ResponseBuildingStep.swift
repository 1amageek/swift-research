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
            return "# \(input.objective)\n\n関連情報を収集できませんでした。"
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

        ## 回答すべき具体的な質問
        \(input.questions.map { "- \($0)" }.joined(separator: "\n"))
        """

        let prompt = """
        あなたは調査結果を報告する専門家です。

        ## ユーザーの問い
        \(input.objective)
        \(questionsSection)

        ## 成功基準
        \(criteriaList)

        ## 収集した情報（関連部分のみ抽出）
        \(contextSection)

        ## 指示
        上記の情報を使って、ユーザーの問いに直接回答してください。

        - 具体的なエビデンスを示す
        - 情報源を明記する
        - 不明な点や情報が不足している点は正直に述べる
        - Markdown形式で読みやすく構造化する
        - ソースURLは後でシステムが追加するため、参照リストは含めない
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
            let response = try await session.respond(generating: FinalResponseBuildingResponse.self) {
                Prompt(prompt)
            }

            if input.verbose {
                printFlush("┌─── LLM OUTPUT (FinalResponse) ───")
                printFlush("responseMarkdown: \(response.content.responseMarkdown.count) chars")
                printFlush(response.content.responseMarkdown.prefix(500))
                printFlush("...")
                printFlush("└─── END LLM OUTPUT ───")
            }

            var responseMarkdown = response.content.responseMarkdown
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
