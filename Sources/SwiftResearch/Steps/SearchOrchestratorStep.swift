import Foundation
import SwiftAgent
import RemarkKit

/// Global log file handle for writing output.
nonisolated(unsafe) var globalLogFileHandle: FileHandle?

/// Lock for thread-safe logging.
private let logLock = NSLock()

/// Thread-safe print that flushes immediately and writes to log file.
@inline(__always)
internal func printFlush(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    logLock.lock()
    defer { logLock.unlock() }

    let output = items.map { String(describing: $0) }.joined(separator: separator)
    print(output, terminator: terminator)
    fflush(stdout)

    if let handle = globalLogFileHandle {
        let logLine = output + terminator
        if let data = logLine.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }
}

/// Orchestrates the complete research workflow from search to response generation.
///
/// The workflow consists of 5 phases:
/// 1. Objective Analysis - Extract keywords and success criteria
/// 2. Search - Find relevant URLs via search engine
/// 3. Parallel Content Review - Fetch and review pages concurrently
/// 4. Sufficiency Check - Determine if enough information is collected
/// 5. Response Building - Generate final response from collected data
///
/// ## Example
///
/// ```swift
/// let session = LanguageModelSession(model: model, tools: [], instructions: nil as String?)
/// let orchestrator = SearchOrchestratorStep(session: session)
/// let result = try await orchestrator.run(SearchQuery(objective: "..."))
/// ```
public struct SearchOrchestratorStep: Step, Sendable {
    public typealias Input = SearchQuery
    public typealias Output = AggregatedResult

    private let session: LanguageModelSession
    private let configuration: CrawlerConfiguration
    private let verbose: Bool
    private let logFileURL: URL?

    /// Creates a new search orchestrator step.
    ///
    /// - Parameters:
    ///   - session: The language model session to use for LLM operations.
    ///   - configuration: The crawler configuration.
    ///   - verbose: Whether to output verbose logging.
    ///   - logFileURL: Optional file URL to write logs to.
    public init(
        session: LanguageModelSession,
        configuration: CrawlerConfiguration = .default,
        verbose: Bool = false,
        logFileURL: URL? = nil
    ) {
        self.session = session
        self.configuration = configuration
        self.verbose = verbose
        self.logFileURL = logFileURL
    }

    public func run(_ input: SearchQuery) async throws -> AggregatedResult {
        let startTime = Date()

        // Set up log file handle
        if let logURL = logFileURL {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            globalLogFileHandle = try? FileHandle(forWritingTo: logURL)
            printFlush("📝 Logging to: \(logURL.path)")
        }
        defer {
            try? globalLogFileHandle?.close()
            globalLogFileHandle = nil
        }

        printFlush("═══════════════════════════════════════════")
        printFlush("🎯 Phase 0: INPUT")
        printFlush("═══════════════════════════════════════════")
        printFlush("objective: \(input.objective)")
        printFlush("maxVisitedURLs: \(input.maxVisitedURLs)")
        printFlush("")

        // ===== Phase 1: Objective Analysis =====
        printFlush("═══════════════════════════════════════════")
        printFlush("📊 Phase 1: OBJECTIVE ANALYSIS")
        printFlush("═══════════════════════════════════════════")
        let phase1Start = Date()
        let analysis = await analyzeObjective(objective: input.objective)
        let phase1Duration = Date().timeIntervalSince(phase1Start)
        printFlush("⏱️ Phase 1 duration: \(String(format: "%.1f", phase1Duration))s")

        if verbose {
            printFlush("keywords: \(analysis.keywords)")
            printFlush("questions: \(analysis.questions)")
            printFlush("successCriteria: \(analysis.successCriteria)")
        }
        printFlush("")

        // Create shared context for parallel crawling
        let context = CrawlContext(
            objective: input.objective,
            successCriteria: analysis.successCriteria,
            maxURLs: input.maxVisitedURLs,
            configuration: configuration.researchConfiguration
        )

        // ===== Phase 2-4 Loop =====
        var usedKeywords: [String] = []
        var pendingKeywords: [String] = analysis.keywords
        var usedKeywordSet: Set<String> = []
        var previousRelevantCount = 0

        while let keyword = pendingKeywords.first {
            pendingKeywords.removeFirst()

            // Check URL limit
            if context.totalProcessed >= input.maxVisitedURLs {
                printFlush("⚠️ URL limit reached (\(input.maxVisitedURLs))")
                break
            }

            // Skip duplicate keywords
            let normalizedKeyword = keyword.lowercased().trimmingCharacters(in: .whitespaces)
            if usedKeywordSet.contains(normalizedKeyword) {
                continue
            }

            usedKeywordSet.insert(normalizedKeyword)
            usedKeywords.append(keyword)

            // ===== Phase 2: Search =====
            printFlush("")
            printFlush("═══════════════════════════════════════════")
            printFlush("🔍 Phase 2: SEARCH [\(keyword)]")
            printFlush("═══════════════════════════════════════════")
            let phase2Start = Date()

            let searchStep = SearchStep(
                searchEngine: configuration.searchEngine,
                blockedDomains: configuration.blockedDomains
            )

            let urls: [URL]
            do {
                urls = try await searchStep.run(KeywordSearchInput(keyword: keyword))
            } catch {
                printFlush("⚠️ Search failed for '\(keyword)': \(error)")
                continue
            }

            let phase2Duration = Date().timeIntervalSince(phase2Start)
            printFlush("⏱️ Phase 2 duration: \(String(format: "%.1f", phase2Duration))s")

            // Filter by allowed domains
            let filteredURLs = urls.filter { isAllowedDomain($0) }
            printFlush("Found \(urls.count) URLs (\(filteredURLs.count) after domain filter):")
            for (i, url) in filteredURLs.enumerated() {
                printFlush("  [\(i+1)] \(url.absoluteString)")
            }

            // Add URLs to queue
            context.enqueueURLs(filteredURLs)
            printFlush("Queue: \(context.queueCount) URLs (after dedup)")
            printFlush("")

            // ===== Phase 3: Parallel Content Review =====
            await parallelContentReview(context: context)

            // ===== Phase 4: Sufficiency Check =====
            printFlush("")
            printFlush("═══════════════════════════════════════════")
            printFlush("✓ Phase 4: SUFFICIENCY CHECK")
            printFlush("═══════════════════════════════════════════")
            let phase4Start = Date()

            let newRelevantThisRound = context.relevantCount - previousRelevantCount

            let sufficiency = await checkSufficiency(
                context: context,
                searchRoundNumber: usedKeywords.count,
                newRelevantThisRound: newRelevantThisRound
            )

            previousRelevantCount = context.relevantCount

            let phase4Duration = Date().timeIntervalSince(phase4Start)
            printFlush("⏱️ Phase 4 duration: \(String(format: "%.1f", phase4Duration))s")

            if verbose {
                printFlush("isSufficient: \(sufficiency.isSufficient)")
                printFlush("shouldGiveUp: \(sufficiency.shouldGiveUp)")
                printFlush("additionalKeywords: \(sufficiency.additionalKeywords)")
                printFlush("reason: \(sufficiency.reasonMarkdown.prefix(200))...")
            }
            printFlush("")

            if sufficiency.isSufficient {
                printFlush("→ SUFFICIENT, exiting loop")
                context.markSufficient()
                break
            } else if sufficiency.shouldGiveUp {
                printFlush("→ GIVE UP, exiting loop")
                break
            } else {
                let newKeywords = sufficiency.additionalKeywords.filter { keyword in
                    let normalized = keyword.lowercased().trimmingCharacters(in: .whitespaces)
                    return !usedKeywordSet.contains(normalized)
                }
                if !newKeywords.isEmpty {
                    printFlush("→ Adding \(newKeywords.count) new keywords: \(newKeywords)")
                    pendingKeywords.append(contentsOf: newKeywords)
                }
            }
        }

        // ===== Phase 5: Response Building =====
        printFlush("")
        printFlush("═══════════════════════════════════════════")
        printFlush("📝 Phase 5: RESPONSE BUILDING")
        printFlush("═══════════════════════════════════════════")
        let phase5Start = Date()

        let reviewedContents = context.reviewedContents
        if verbose {
            printFlush("input reviewedContents: \(reviewedContents.count) items")
            for (i, c) in reviewedContents.prefix(10).enumerated() {
                printFlush("  [\(i+1)] \(c.url.host ?? "?"): \(c.extractedInfo.prefix(60))...")
            }
        }

        let responseMarkdown = await buildFinalResponse(
            reviewedContents: reviewedContents,
            objective: input.objective
        )

        let phase5Duration = Date().timeIntervalSince(phase5Start)
        printFlush("⏱️ Phase 5 duration: \(String(format: "%.1f", phase5Duration))s")
        printFlush("output responseMarkdown: \(responseMarkdown.count) chars")

        let endTime = Date()

        let statistics = AggregatedStatistics(
            totalPagesVisited: context.totalProcessed,
            relevantPagesFound: context.relevantCount,
            keywordsUsed: usedKeywords.count,
            duration: Duration.seconds(endTime.timeIntervalSince(startTime))
        )

        printFlush("")
        printFlush("🏁 Complete!")
        printFlush("   Visited: \(statistics.totalPagesVisited), Relevant: \(statistics.relevantPagesFound)")
        printFlush("   Keywords: \(statistics.keywordsUsed)")
        printFlush("   Duration: \(String(format: "%.1f", endTime.timeIntervalSince(startTime)))s")

        return AggregatedResult(
            objective: input.objective,
            questions: analysis.questions,
            successCriteria: analysis.successCriteria,
            reviewedContents: reviewedContents,
            responseMarkdown: responseMarkdown,
            keywordsUsed: usedKeywords,
            statistics: statistics
        )
    }

    // MARK: - Phase 1: Objective Analysis

    private func analyzeObjective(objective: String) async -> ObjectiveAnalysis {
        let prompt = """
        あなたは情報収集エージェントです。目的を分析してください。

        ## 目的
        \(objective)

        ## あなたの任務

        ### 1. 検索キーワード（keywords）
        目的を達成するための検索キーワードを3〜5個生成。
        - 英語で記述
        - 検索エンジン向け

        ### 2. 具体的な問い（questions）
        目的を達成するために答えるべき具体的な問いを3つ生成。
        - 明確化: 何を意味しているか？
        - 前提検証: 何を前提としているか？
        - 含意探索: 何が導かれるか？

        ### 3. 成功基準（successCriteria）
        情報収集が十分と判断する条件を2〜3個。
        - 具体的で検証可能な基準
        """

        if verbose {
            printFlush("┌─── LLM INPUT (ObjectiveAnalysis) ───")
            printFlush(prompt)
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        do {
            let response = try await session.respond(generating: ObjectiveAnalysisResponse.self) {
                Prompt(prompt)
            }

            if verbose {
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
                return ObjectiveAnalysis.fallback(objective: objective)
            }

            let uniqueKeywords = Array(Set(rawAnalysis.keywords)).prefix(5)
            let uniqueQuestions = Array(Set(rawAnalysis.questions)).prefix(5)
            let uniqueCriteria = Array(Set(rawAnalysis.successCriteria)).prefix(3)

            return ObjectiveAnalysis(
                keywords: Array(uniqueKeywords),
                questions: Array(uniqueQuestions),
                successCriteria: Array(uniqueCriteria)
            )
        } catch {
            printFlush("⚠️ Objective analysis failed: \(error)")
            return ObjectiveAnalysis.fallback(objective: objective)
        }
    }

    // MARK: - Phase 3: Parallel Content Review

    private func parallelContentReview(context: CrawlContext) async {
        printFlush("═══════════════════════════════════════════")
        printFlush("📄 Phase 3: PARALLEL CONTENT REVIEW")
        printFlush("═══════════════════════════════════════════")
        printFlush("   Queue: \(context.queueCount) URLs, Concurrency: \(context.maxConcurrent)")

        let phase3Start = Date()

        await withTaskGroup(of: Void.self) { group in
            for workerID in 0..<context.maxConcurrent {
                group.addTask {
                    await self.worker(id: workerID, context: context)
                }
            }
        }

        let phase3Duration = Date().timeIntervalSince(phase3Start)
        let stats = context.getStatistics()
        printFlush("")
        printFlush("Phase 3 Summary: processed=\(stats.processed), relevant=\(stats.relevant)")
        printFlush("⏱️ Phase 3 total: \(String(format: "%.1f", phase3Duration))s")
    }

    private func worker(id: Int, context: CrawlContext) async {
        while let url = context.dequeueURL() {
            // Process until dequeueURL() returns nil
            // (isSufficient/maxURLs/empty queue checks are performed atomically in dequeueURL)

            let pageStart = Date()
            let host = url.host ?? url.absoluteString
            printFlush("   [W\(id)] → \(host)")

            let result = await fetchAndReview(url: url, context: context)

            context.completeURL(url)

            let pageDuration = Date().timeIntervalSince(pageStart)

            if let result = result {
                context.addResult(result.reviewed)

                // Add deep crawl URLs to queue
                if let deepURLs = result.deepURLs, !deepURLs.isEmpty {
                    context.enqueueURLs(deepURLs)
                    printFlush("   [W\(id)]    +\(deepURLs.count) deep URLs")
                }

                let status = result.reviewed.isRelevant ? "✓" : "·"
                let info = result.reviewed.extractedInfo.prefix(60)
                printFlush("   [W\(id)] \(status) \(String(format: "%.1fs", pageDuration)) \(info)...")
            } else {
                printFlush("   [W\(id)] ✗ \(String(format: "%.1fs", pageDuration)) fetch failed")
            }

            // Request delay
            try? await Task.sleep(for: configuration.requestDelay)
        }
    }

    // MARK: - Fetch and Review

    private struct FetchReviewResult: Sendable {
        let reviewed: ReviewedContent
        let deepURLs: [URL]?
        let fetchDuration: TimeInterval
        let llmDuration: TimeInterval
    }

    private func fetchAndReview(url: URL, context: CrawlContext) async -> FetchReviewResult? {
        // Fetch with timeout
        let fetchStart = Date()
        let remark: Remark
        let links: [Link]

        do {
            remark = try await withThrowingTaskGroup(of: Remark.self) { group in
                group.addTask {
                    try await Remark.fetch(from: url)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            links = try remark.extractLinks()
        } catch {
            if verbose {
                printFlush("   ⚠️ Fetch failed: \(url.absoluteString) - \(error)")
            }
            return nil
        }
        let fetchDuration = Date().timeIntervalSince(fetchStart)

        // Get known facts to improve review accuracy
        let knownFacts = context.getKnownFacts()
        let relevantDomains = context.getRelevantDomains()

        // Review
        let llmStart = Date()
        let review = await reviewContent(
            markdown: remark.markdown,
            title: remark.title,
            links: links,
            sourceURL: url,
            objective: context.objective,
            knownFacts: knownFacts,
            relevantDomains: relevantDomains
        )
        let llmDuration = Date().timeIntervalSince(llmStart)

        let reviewed = ReviewedContent(
            url: url,
            title: remark.title.isEmpty ? nil : remark.title,
            extractedInfo: review.extractedInfo,
            isRelevant: review.isRelevant
        )

        // Extract deep crawl URLs if not already sufficient
        var deepURLs: [URL]? = nil
        if review.shouldDeepCrawl && !review.priorityLinks.isEmpty && !context.isSufficient {
            deepURLs = extractDeepURLs(
                priorityLinks: review.priorityLinks,
                links: links,
                sourceURL: url,
                context: context
            )
        }

        return FetchReviewResult(
            reviewed: reviewed,
            deepURLs: deepURLs,
            fetchDuration: fetchDuration,
            llmDuration: llmDuration
        )
    }

    private func reviewContent(
        markdown: String,
        title: String,
        links: [Link],
        sourceURL: URL,
        objective: String,
        knownFacts: [String],
        relevantDomains: Set<String>
    ) async -> ContentReview {
        let maxChars = configuration.researchConfiguration.contentMaxChars
        let truncatedContent = String(markdown.prefix(maxChars))

        let linksInfo = links.prefix(5).enumerated().map { index, link in
            "[\(index + 1)] \(link.text.isEmpty ? "-" : String(link.text.prefix(30))) -> \(link.url)"
        }.joined(separator: "\n")

        let knownFactsSection = knownFacts.isEmpty ? "" : """

        ## 既に収集した情報（重複を避けること）
        \(knownFacts.map { "- \($0.prefix(100))" }.joined(separator: "\n"))
        """

        let prompt = """
        目的に関連する**新しい**情報を抽出してください。

        ## 目的
        \(objective)
        \(knownFactsSection)

        ## ページ: \(title)
        \(truncatedContent)

        ## リンク
        \(linksInfo)

        ## 出力（簡潔に）
        - isRelevant: 新しい関連情報があるか
        - extractedInfo: 関連情報（100-150字、既知と重複しない）
        - shouldDeepCrawl: 深掘りすべきか
        - priorityLinks: 深掘り候補（最大2件）
        """

        if verbose {
            printFlush("    ┌─── LLM INPUT (ContentReview) ───")
            printFlush("    objective: \(objective)")
            printFlush("    title: \(title)")
            printFlush("    content: \(truncatedContent.prefix(200))...")
            printFlush("    knownFacts: \(knownFacts.count) items")
            printFlush("    └─── END LLM INPUT ───")
        }

        do {
            let response = try await session.respond(generating: ContentReviewResponse.self) {
                Prompt(prompt)
            }

            if verbose {
                printFlush("    ┌─── LLM OUTPUT (ContentReview) ───")
                printFlush("    isRelevant: \(response.content.isRelevant)")
                printFlush("    extractedInfo: \(response.content.extractedInfo)")
                printFlush("    shouldDeepCrawl: \(response.content.shouldDeepCrawl)")
                printFlush("    priorityLinks: \(response.content.priorityLinks.count) items")
                printFlush("    └─── END LLM OUTPUT ───")
            }

            return ContentReview(from: response.content)
        } catch {
            if verbose {
                printFlush("   ⚠️ Review failed: \(error)")
            }
            return ContentReview.irrelevant()
        }
    }

    private func extractDeepURLs(
        priorityLinks: [PriorityLink],
        links: [Link],
        sourceURL: URL,
        context: CrawlContext
    ) -> [URL] {
        var deepURLs: [URL] = []
        let relevantDomains = context.getRelevantDomains()

        let sortedLinks = priorityLinks.sorted { $0.score > $1.score }

        for priorityLink in sortedLinks.prefix(2) {
            guard priorityLink.index > 0 && priorityLink.index <= links.count else { continue }

            let link = links[priorityLink.index - 1]
            guard let resolvedURL = URL(string: link.url, relativeTo: sourceURL)?.absoluteURL else { continue }

            // Check domain filter
            guard isAllowedDomain(resolvedURL) else { continue }

            // Check if already visited
            guard !context.isVisited(resolvedURL) else { continue }

            // Prioritize relevant domains
            if let host = resolvedURL.host, relevantDomains.contains(host) {
                deepURLs.insert(resolvedURL, at: 0)
            } else {
                deepURLs.append(resolvedURL)
            }
        }

        return deepURLs
    }

    // MARK: - Phase 4: Sufficiency Check

    private func checkSufficiency(
        context: CrawlContext,
        searchRoundNumber: Int,
        newRelevantThisRound: Int
    ) async -> SufficiencyResult {
        let reviewedContents = context.reviewedContents

        guard !reviewedContents.isEmpty else {
            return SufficiencyResult.insufficient(reason: "まだ関連情報が収集できていません")
        }

        let collectedInfo = reviewedContents
            .filter { $0.isRelevant }
            .prefix(10)
            .map { content in
                "【\(content.url.host ?? "unknown")】\(content.extractedInfo)"
            }
            .joined(separator: "\n")

        let criteriaList = context.successCriteria.enumerated()
            .map { "- \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        あなたは情報充足度を判断するエージェントです。

        ## 目的
        \(context.objective)

        ## 成功基準
        \(criteriaList)

        ## 検索履歴
        - 検索ラウンド: \(searchRoundNumber)回目
        - このラウンドで見つかった新規関連ページ: \(newRelevantThisRound)件
        - 累計関連ページ: \(context.relevantCount)件

        ## これまでに収集した情報
        \(collectedInfo)

        ## 判断基準

        1. isSufficient: ユーザーが目的を達成できる状態か？
           - 一次情報源（公式サイト、ドキュメント等）が見つかった
           - 目的に対する概要や主要情報が把握できた

        2. shouldGiveUp: これ以上の情報収集は困難か？
           - このラウンドで新規関連ページが0件だった
           - 複数ラウンド経過しても情報が増えていない

        3. additionalKeywords: 本当に不足している場合のみ追加（最大2個）

        4. reasonMarkdown: 判断理由（簡潔に）
        """

        if verbose {
            printFlush("┌─── LLM INPUT (SufficiencyCheck) ───")
            printFlush("objective: \(context.objective)")
            printFlush("successCriteria: \(context.successCriteria)")
            printFlush("searchRound: \(searchRoundNumber), newRelevantThisRound: \(newRelevantThisRound)")
            printFlush("collectedInfo: \(reviewedContents.count) items")
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        do {
            let response = try await session.respond(generating: SufficiencyCheckResponse.self) {
                Prompt(prompt)
            }

            if verbose {
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

    // MARK: - Phase 5: Response Building

    private func buildFinalResponse(
        reviewedContents: [ReviewedContent],
        objective: String
    ) async -> String {
        guard !reviewedContents.isEmpty else {
            return "# \(objective)\n\n関連情報を収集できませんでした。"
        }

        let relevantContents = reviewedContents.filter { $0.isRelevant }

        let collectedInfo = relevantContents.enumerated().map { index, content in
            "[\(index + 1)] \(content.url.host ?? "unknown"): \(content.extractedInfo)"
        }.joined(separator: "\n")

        let prompt = """
        あなたはレポートを作成する専門家です。

        ## 目的
        \(objective)

        ## 収集した情報
        \(collectedInfo)

        ## あなたの任務

        収集した情報に基づいて、目的に対する包括的な回答をMarkdown形式で作成してください。

        - 具体的な情報とエビデンスを含める
        - 読みやすい構造で記述
        - ソースURLは後でシステムが追加するため、参照リストは含めない
        """

        if verbose {
            printFlush("┌─── LLM INPUT (FinalResponse) ───")
            printFlush("objective: \(objective)")
            printFlush("collectedInfo: \(relevantContents.count) items")
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        do {
            let response = try await session.respond(generating: FinalResponseBuildingResponse.self) {
                Prompt(prompt)
            }

            if verbose {
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
            var fallback = "# \(objective)\n\n"
            fallback += collectedInfo
            fallback += "\n\n## 参照ソース\n"
            for content in relevantContents {
                fallback += "- \(content.url.absoluteString)\n"
            }
            return fallback
        }
    }

    // MARK: - Domain Filtering

    private func isAllowedDomain(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        let builtInBlockedDomains = [
            "apps.apple.com", "play.google.com",
            "twitter.com", "x.com", "facebook.com", "linkedin.com", "instagram.com", "youtube.com",
            "amazon.com", "amazon.co.jp",
            "policy.medium.com", "help.medium.com",
            "support.google.com", "accounts.google.com", "about.google.com", "policies.google.com",
        ]

        if builtInBlockedDomains.contains(where: { host.contains($0) }) {
            return false
        }

        if configuration.blockedDomains.contains(where: { host.contains($0) }) {
            return false
        }

        let blockedPaths = [
            "/login", "/signin", "/sign_in", "/sign-in",
            "/signup", "/sign_up", "/sign-up", "/register",
            "/privacy", "/terms", "/tos",
            "/cart", "/checkout", "/buy",
            "/share", "/tweet",
        ]

        let path = url.path.lowercased()
        if blockedPaths.contains(where: { path.contains($0) }) {
            return false
        }

        if let allowed = configuration.allowedDomains {
            return allowed.contains(where: { host.contains($0) })
        }

        return true
    }
}
