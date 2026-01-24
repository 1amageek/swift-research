import Foundation
import SwiftAgent
import RemarkKit

/// Input for content review.
public struct ContentReviewInput: Sendable {
    /// The markdown content of the page.
    public let markdown: String

    /// The page title.
    public let title: String

    /// Links extracted from the page.
    public let links: [Link]

    /// The source URL of the page.
    public let sourceURL: URL

    /// The research objective.
    public let objective: String

    /// Known facts to avoid duplication.
    public let knownFacts: [String]

    /// Domains that have yielded relevant content.
    public let relevantDomains: Set<String>

    /// Whether to enable verbose logging.
    public let verbose: Bool

    public init(
        markdown: String,
        title: String,
        links: [Link],
        sourceURL: URL,
        objective: String,
        knownFacts: [String],
        relevantDomains: Set<String>,
        verbose: Bool = false
    ) {
        self.markdown = markdown
        self.title = title
        self.links = links
        self.sourceURL = sourceURL
        self.objective = objective
        self.knownFacts = knownFacts
        self.relevantDomains = relevantDomains
        self.verbose = verbose
    }
}

/// Phase 3: Content Review Step.
///
/// Reviews page content to extract relevant information for the research objective.
/// Uses LLM to analyze content, determine relevance, and identify priority links for deep crawling.
///
/// ## Example
///
/// ```swift
/// // Run within context that provides ModelContext and config
/// let input = ContentReviewInput(
///     markdown: remark.markdown,
///     title: remark.title,
///     links: links,
///     sourceURL: url,
///     objective: "...",
///     knownFacts: [],
///     relevantDomains: []
/// )
/// let review = try await ContentReviewStep().run(input)
/// ```
public struct ContentReviewStep: Step, Sendable {
    public typealias Input = ContentReviewInput
    public typealias Output = ContentReview

    @Context var modelContext: ModelContext
    @Context var config: CrawlerConfiguration

    public init() {}

    public func run(_ input: ContentReviewInput) async throws -> ContentReview {
        let session = LanguageModelSession(
            model: modelContext.model,
            tools: [],
            instructions: StepInstructions.contentReview
        )

        let maxChars = config.researchConfiguration.contentMaxChars

        // Add line numbers to markdown for relevantRanges extraction
        let lines = input.markdown.components(separatedBy: "\n")
        let numberedLines = lines.enumerated().map { index, line in
            "\(index): \(line)"
        }
        let numberedContent = numberedLines.joined(separator: "\n")
        let truncatedContent = String(numberedContent.prefix(maxChars))

        let linksInfo = input.links.prefix(5).enumerated().map { index, link in
            "[\(index + 1)] \(link.text.isEmpty ? "-" : String(link.text.prefix(30))) -> \(link.url)"
        }.joined(separator: "\n")

        let knownFactsSection = input.knownFacts.isEmpty ? "" : """

        ## 既に収集した情報（重複を避けること）
        \(input.knownFacts.map { "- \($0.prefix(100))" }.joined(separator: "\n"))
        """

        let domainSection = config.domainContext.map { context in
            """

            ## Domain Context
            \(context)
            Evaluate relevance from this domain's perspective.
            """
        } ?? ""

        let prompt = """
        目的に関連する**新しい**情報を抽出してください。

        ## 目的
        \(input.objective)
        \(knownFactsSection)
        \(domainSection)

        ## ページ: \(input.title)（行番号付き）
        \(truncatedContent)

        ## リンク
        \(linksInfo)

        ## 出力
        - isRelevant: 新しい関連情報があるか
        - extractedInfo: 関連情報の要約（100-150字、既知と重複しない）
        - shouldDeepCrawl: 深掘りすべきか
        - priorityLinks: 深掘り候補のリンク
        - relevantRanges: 関連情報が含まれる行範囲（start: 開始行, end: 終了行）

        IMPORTANT: Respond with a valid JSON object only. Do not include markdown formatting or code fences.
        """

        if input.verbose {
            printFlush("    ┌─── LLM INPUT (ContentReview) ───")
            printFlush("    objective: \(input.objective)")
            printFlush("    title: \(input.title)")
            printFlush("    content: \(truncatedContent.prefix(200))...")
            printFlush("    knownFacts: \(input.knownFacts.count) items")
            printFlush("    └─── END LLM INPUT ───")
        }

        do {
            let generateStep = Generate<String, ContentReviewResponse>(
                session: session,
                prompt: { Prompt($0) }
            )
            let response = try await generateStep.run(prompt)

            if input.verbose {
                printFlush("    ┌─── LLM OUTPUT (ContentReview) ───")
                printFlush("    isRelevant: \(response.isRelevant)")
                printFlush("    extractedInfo: \(response.extractedInfo)")
                printFlush("    shouldDeepCrawl: \(response.shouldDeepCrawl)")
                printFlush("    priorityLinks: \(response.priorityLinks.count) items")
                printFlush("    relevantRanges: \(response.relevantRanges.map { "\($0.start)..<\($0.end)" })")
                printFlush("    └─── END LLM OUTPUT ───")
            }

            return ContentReview(from: response)
        } catch {
            if input.verbose {
                printFlush("   ⚠️ Review failed: \(error)")
            }
            return ContentReview.irrelevant()
        }
    }
}
