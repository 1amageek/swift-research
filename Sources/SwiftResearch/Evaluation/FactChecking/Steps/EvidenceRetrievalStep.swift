import Foundation
import SwiftAgent
import RemarkKit

// MARK: - Input

/// Input for evidence retrieval.
public struct EvidenceRetrievalInput: Sendable {
    /// The statement to find evidence for.
    public let statement: VerifiableStatement

    /// Number of evidence pieces to retrieve.
    public let evidenceCount: Int

    /// Search queries to use (if not provided, will be generated).
    public let searchQueries: [String]?

    /// Creates a new evidence retrieval input.
    ///
    /// - Parameters:
    ///   - statement: The statement to verify.
    ///   - evidenceCount: Number of evidence pieces to retrieve.
    ///   - searchQueries: Optional search queries to use.
    public init(
        statement: VerifiableStatement,
        evidenceCount: Int = 3,
        searchQueries: [String]? = nil
    ) {
        self.statement = statement
        self.evidenceCount = evidenceCount
        self.searchQueries = searchQueries
    }
}

// MARK: - EvidenceRetrievalStep

/// A step that retrieves evidence from the web to verify a statement.
///
/// Uses web search to find sources that can support or contradict the statement,
/// then analyzes each source to extract relevant evidence.
///
/// ```swift
/// let step = EvidenceRetrievalStep()
/// let evidence = try await step
///     .context(ModelContext(model))
///     .context(crawlerConfig)
///     .run(EvidenceRetrievalInput(statement: statement, evidenceCount: 3))
/// ```
public struct EvidenceRetrievalStep: Step, Sendable {
    public typealias Input = EvidenceRetrievalInput
    public typealias Output = [Evidence]

    @Context private var modelContext: ModelContext
    @Context private var crawlerConfig: CrawlerConfiguration

    /// Creates a new evidence retrieval step.
    public init() {}

    public func run(_ input: EvidenceRetrievalInput) async throws -> [Evidence] {
        // Generate search queries if not provided
        let queries = try await getSearchQueries(for: input)

        // Search for URLs
        var allURLs: [URL] = []
        for query in queries.prefix(2) {
            do {
                let searchStep = SearchStep(
                    searchEngine: crawlerConfig.searchEngine,
                    blockedDomains: crawlerConfig.blockedDomains
                )
                let urls = try await searchStep.run(KeywordSearchInput(keyword: query))
                allURLs.append(contentsOf: urls)
            } catch {
                // Continue with other queries if one fails
                continue
            }
        }

        // Remove duplicates
        let uniqueURLs = Array(Set(allURLs))

        // Fetch and analyze pages
        var evidence: [Evidence] = []

        for url in uniqueURLs.prefix(input.evidenceCount * 2) {
            guard evidence.count < input.evidenceCount else { break }

            do {
                let pageEvidence = try await analyzePageForEvidence(
                    url: url,
                    statement: input.statement
                )
                if let e = pageEvidence {
                    evidence.append(e)
                }
            } catch {
                // Skip pages that fail to fetch
                continue
            }
        }

        return evidence
    }

    private func getSearchQueries(for input: EvidenceRetrievalInput) async throws -> [String] {
        // Priority 1: Explicitly provided search queries
        if let queries = input.searchQueries, !queries.isEmpty {
            return queries
        }

        // Priority 2: Use the LLM-suggested query from statement extraction
        if let suggestedQuery = input.statement.suggestedSearchQuery {
            return [suggestedQuery]
        }

        // Priority 3: Generate new search queries using LLM (fallback)
        let session = LanguageModelSession(
            model: modelContext.model,
            tools: [],
            instructions: "あなたは検索クエリ生成アシスタントです。事実検証のための効果的な検索クエリを生成してください。"
        )

        let prompt = """
        以下の声明を検証するための検索クエリを生成してください:

        声明: \(input.statement.text)
        種類: \(input.statement.type.rawValue)

        この声明を検証または反証するための証拠を見つけるための2-3個の検索クエリを生成してください。
        信頼性の高いソースを見つけることに重点を置いてください。
        """

        let response = try await session.respond(
            to: prompt,
            generating: VerificationSearchQueryResponse.self
        )

        return response.content.queries
    }

    private func analyzePageForEvidence(
        url: URL,
        statement: VerifiableStatement
    ) async throws -> Evidence? {
        // Fetch page content with timeout
        let remark = try await Remark.fetch(from: url, timeout: 10)
        let content = String(remark.markdown.prefix(5000))

        // Create session for analysis
        let session = LanguageModelSession(
            model: modelContext.model,
            tools: [],
            instructions: "あなたは証拠分析アシスタントです。ページ内容を分析し、声明に対する証拠を抽出してください。"
        )

        let prompt = """
        以下のページ内容を分析し、声明に対する証拠となるかどうかを判断してください:

        声明: \(statement.text)

        ページタイトル: \(remark.title)
        ページ内容:
        ---
        \(content)
        ---

        判断項目:
        1. このページに関連する証拠が含まれているか
        2. 証拠は声明を支持するか、反論するか
        3. このソースの信頼性はどの程度か

        関連する証拠が見つからない場合は、supportLevel を "Neutral" としてください。
        """

        let response = try await session.respond(
            to: prompt,
            generating: EvidenceAnalysisResponse.self
        )

        let analysisResult = response.content

        // Skip if neutral and not useful
        guard analysisResult.supportLevel != SupportLevel.neutral || !analysisResult.relevantText.isEmpty else {
            return nil
        }

        return Evidence(
            sourceURL: url,
            sourceTitle: remark.title,
            relevantText: analysisResult.relevantText,
            supportLevel: analysisResult.supportLevel,
            sourceCredibility: analysisResult.sourceCredibility
        )
    }
}
