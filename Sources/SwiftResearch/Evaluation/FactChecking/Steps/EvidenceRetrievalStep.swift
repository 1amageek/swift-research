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
///     .session(session)
///     .context(CrawlerConfiguration.self, value: config)
///     .run(EvidenceRetrievalInput(statement: statement, evidenceCount: 3))
/// ```
public struct EvidenceRetrievalStep: Step, Sendable {
    public typealias Input = EvidenceRetrievalInput
    public typealias Output = [Evidence]

    @Session private var session: LanguageModelSession
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
        // This avoids redundant LLM calls since the extraction model already analyzed the statement
        if let suggestedQuery = input.statement.suggestedSearchQuery {
            return [suggestedQuery]
        }

        // Priority 3: Generate new search queries using LLM (fallback)
        let prompt = """
        Generate search queries to verify the following statement:

        Statement: \(input.statement.text)
        Type: \(input.statement.type.rawValue)

        Generate 2-3 search queries that would help find evidence to verify or refute this statement.
        Focus on finding authoritative sources.
        """

        let response = try await session.respond(generating: VerificationSearchQueryResponse.self) {
            Prompt(prompt)
        }

        return response.content.queries
    }

    private func analyzePageForEvidence(
        url: URL,
        statement: VerifiableStatement
    ) async throws -> Evidence? {
        // Fetch page content with timeout
        let remark = try await Remark.fetch(from: url, timeout: 10)
        let content = String(remark.markdown.prefix(5000))

        // Analyze for evidence
        let prompt = """
        Analyze the following page content to determine if it provides evidence
        for or against this statement:

        Statement: \(statement.text)

        Page Title: \(remark.title)
        Page Content:
        ---
        \(content)
        ---

        Determine:
        1. Does this page contain relevant evidence?
        2. How does the evidence support or contradict the statement?
        3. What is the credibility of this source?

        If no relevant evidence is found, indicate "neutral" support level.
        """

        let response = try await session.respond(generating: EvidenceAnalysisResponse.self) {
            Prompt(prompt)
        }

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
