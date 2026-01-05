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

// MARK: - Error Classification

/// Represents the type of fetch error for retry logic.
enum FetchErrorType: Sendable {
    case timeout
    case networkConnection
    case httpError(statusCode: Int)
    case cancelled
    case parsing
    case unknown

    /// Whether this error type should be retried.
    var isRetryable: Bool {
        switch self {
        case .timeout, .networkConnection:
            return true
        case .httpError(let statusCode):
            // Retry on 5xx server errors, but not on 4xx client errors
            return statusCode >= 500
        case .cancelled, .parsing, .unknown:
            return false
        }
    }

    /// Human-readable description of the error type.
    var description: String {
        switch self {
        case .timeout:
            return "timeout"
        case .networkConnection:
            return "network connection"
        case .httpError(let statusCode):
            return "HTTP \(statusCode)"
        case .cancelled:
            return "cancelled"
        case .parsing:
            return "parsing"
        case .unknown:
            return "unknown"
        }
    }
}

/// Classifies an error into a FetchErrorType for retry logic.
func classifyFetchError(_ error: Error) -> FetchErrorType {
    // Check for CancellationError (from our timeout mechanism)
    if error is CancellationError {
        return .timeout
    }

    // Check error description for Remark's ValidationError timeout
    let errorDescription = String(describing: error).lowercased()
    if errorDescription.contains("timeout") || errorDescription.contains("timed out") {
        return .timeout
    }

    // Check NSError for network errors
    let nsError = error as NSError

    // NSURLErrorDomain error codes
    switch nsError.code {
    case -1001: // NSURLErrorTimedOut
        return .timeout
    case -1009, // NSURLErrorNotConnectedToInternet
         -1004, // NSURLErrorCannotConnectToHost
         -1005, // NSURLErrorNetworkConnectionLost
         -1020: // NSURLErrorDataNotAllowed
        return .networkConnection
    default:
        break
    }

    // Check for HTTP status errors in userInfo
    if nsError.userInfo["NSErrorFailingURLKey"] is URL,
       let statusCode = nsError.userInfo["_kCFStreamErrorCodeKey"] as? Int {
        return .httpError(statusCode: statusCode)
    }

    // Check for SwiftSoup parsing errors
    if errorDescription.contains("parse") || errorDescription.contains("swiftsoup") {
        return .parsing
    }

    return .unknown
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
/// Factory closure for creating LanguageModelSession instances.
///
/// Used when LLM does not support concurrent requests.
public typealias SessionFactory = @Sendable () -> LanguageModelSession

public struct SearchOrchestratorStep: Step, Sendable {
    public typealias Input = SearchQuery
    public typealias Output = AggregatedResult

    private let session: LanguageModelSession
    private let sessionFactory: SessionFactory?
    private let configuration: CrawlerConfiguration
    private let verbose: Bool
    private let logFileURL: URL?
    private let progressContinuation: AsyncStream<CrawlProgress>.Continuation?

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
        self.sessionFactory = nil
        self.configuration = configuration
        self.verbose = verbose
        self.logFileURL = logFileURL
        self.progressContinuation = nil
    }

    /// Creates a new search orchestrator step with progress reporting.
    ///
    /// - Parameters:
    ///   - session: The language model session to use for LLM operations.
    ///   - configuration: The crawler configuration.
    ///   - verbose: Whether to output verbose logging.
    ///   - logFileURL: Optional file URL to write logs to.
    ///   - progressContinuation: Continuation to send progress updates.
    public init(
        session: LanguageModelSession,
        configuration: CrawlerConfiguration = .default,
        verbose: Bool = false,
        logFileURL: URL? = nil,
        progressContinuation: AsyncStream<CrawlProgress>.Continuation?
    ) {
        self.session = session
        self.sessionFactory = nil
        self.configuration = configuration
        self.verbose = verbose
        self.logFileURL = logFileURL
        self.progressContinuation = progressContinuation
    }

    /// Creates a new search orchestrator step with a session factory.
    ///
    /// Use this initializer when the LLM does not support concurrent requests.
    /// Each worker will create its own session using the factory.
    ///
    /// - Parameters:
    ///   - session: The language model session for non-parallel operations (Phase 1, 4, 5).
    ///   - sessionFactory: Factory to create worker-specific sessions for Phase 3.
    ///   - configuration: The crawler configuration.
    ///   - verbose: Whether to output verbose logging.
    ///   - logFileURL: Optional file URL to write logs to.
    ///   - progressContinuation: Continuation to send progress updates.
    public init(
        session: LanguageModelSession,
        sessionFactory: @escaping SessionFactory,
        configuration: CrawlerConfiguration = .default,
        verbose: Bool = false,
        logFileURL: URL? = nil,
        progressContinuation: AsyncStream<CrawlProgress>.Continuation? = nil
    ) {
        self.session = session
        self.sessionFactory = sessionFactory
        self.configuration = configuration
        self.verbose = verbose
        self.logFileURL = logFileURL
        self.progressContinuation = progressContinuation
    }

    /// Sends a progress update if continuation is available.
    private func sendProgress(_ progress: CrawlProgress) {
        progressContinuation?.yield(progress)
    }

    /// Creates a session for a worker.
    ///
    /// If `llmSupportsConcurrency` is true or no factory is provided, returns the shared session.
    /// Otherwise, creates a new session using the factory.
    private func createWorkerSession() -> LanguageModelSession {
        if configuration.researchConfiguration.llmSupportsConcurrency {
            return session
        }
        if let factory = sessionFactory {
            return factory()
        }
        // Fallback: return shared session (may cause errors with non-concurrent LLMs)
        return session
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

        sendProgress(.started(objective: input.objective))

        // ===== Phase 1: Objective Analysis =====
        printFlush("═══════════════════════════════════════════")
        printFlush("📊 Phase 1: OBJECTIVE ANALYSIS")
        printFlush("═══════════════════════════════════════════")
        sendProgress(.phaseChanged(phase: .analyzing))
        let phase1Start = Date()
        let analysis = await analyzeObjective(objective: input.objective)
        let phase1Duration = Date().timeIntervalSince(phase1Start)
        printFlush("⏱️ Phase 1 duration: \(String(format: "%.1f", phase1Duration))s")

        sendProgress(.keywordsGenerated(keywords: analysis.keywords))

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
            sendProgress(.phaseChanged(phase: .searching))
            sendProgress(.searchStarted(keyword: keyword))
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
                sendProgress(.error(message: "Search failed for '\(keyword)': \(error)"))
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

            sendProgress(.urlsFound(keyword: keyword, urls: filteredURLs))

            // Add URLs to queue
            context.enqueueURLs(filteredURLs)
            printFlush("Queue: \(context.queueCount) URLs (after dedup)")
            printFlush("")

            // ===== Phase 3: Parallel Content Review =====
            sendProgress(.phaseChanged(phase: .reviewing))
            await parallelContentReview(context: context)

            // ===== Phase 4: Sufficiency Check =====
            printFlush("")
            printFlush("═══════════════════════════════════════════")
            printFlush("✓ Phase 4: SUFFICIENCY CHECK")
            printFlush("═══════════════════════════════════════════")
            sendProgress(.phaseChanged(phase: .checkingSufficiency))
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

            sendProgress(.sufficiencyChecked(isSufficient: sufficiency.isSufficient, reason: sufficiency.reasonMarkdown))

            // Update success criteria with refined version from Phase 4
            context.updateSuccessCriteria(sufficiency.successCriteria)

            if verbose {
                printFlush("isSufficient: \(sufficiency.isSufficient)")
                printFlush("shouldGiveUp: \(sufficiency.shouldGiveUp)")
                printFlush("additionalKeywords: \(sufficiency.additionalKeywords)")
                printFlush("successCriteria: \(sufficiency.successCriteria)")
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
                    sendProgress(.additionalKeywords(keywords: newKeywords))
                    pendingKeywords.append(contentsOf: newKeywords)
                }
            }
        }

        // ===== Phase 5: Response Building =====
        printFlush("")
        printFlush("═══════════════════════════════════════════")
        printFlush("📝 Phase 5: RESPONSE BUILDING")
        printFlush("═══════════════════════════════════════════")
        sendProgress(.phaseChanged(phase: .buildingResponse))
        sendProgress(.buildingResponse)
        let phase5Start = Date()

        let reviewedContents = context.reviewedContents
        let relevantExcerpts = context.getRelevantContext()
        if verbose {
            printFlush("input reviewedContents: \(reviewedContents.count) items")
            printFlush("input relevantExcerpts: \(relevantExcerpts.count) pages with excerpts")
            for (i, c) in reviewedContents.prefix(10).enumerated() {
                printFlush("  [\(i+1)] \(c.url.host ?? "?"): \(c.extractedInfo.prefix(60))...")
            }
        }

        let responseMarkdown = await buildFinalResponse(
            relevantExcerpts: relevantExcerpts,
            reviewedContents: reviewedContents,
            objective: input.objective,
            questions: analysis.questions
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

        sendProgress(.phaseChanged(phase: .completed))
        sendProgress(.completed(statistics: statistics))

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
        情報収集が十分と判断するための具体的な条件。
        - 目的の複雑さに応じて必要な数だけ列挙
        - 「〜が判明した」「〜を確認できた」のように具体的・検証可能に記述
        - 曖昧な表現（detailed, comprehensive, thorough等）は使用禁止
        """

        if verbose {
            printFlush("┌─── LLM INPUT (ObjectiveAnalysis) ───")
            printFlush(prompt)
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        sendProgress(.promptSent(phase: "Phase 1: Objective Analysis", prompt: prompt))

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
            let uniqueCriteria = Array(Set(rawAnalysis.successCriteria))

            return ObjectiveAnalysis(
                keywords: Array(uniqueKeywords),
                questions: Array(uniqueQuestions),
                successCriteria: uniqueCriteria
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
                    // Each worker gets its own session when LLM doesn't support concurrency
                    let workerSession = self.createWorkerSession()
                    await self.worker(id: workerID, context: context, session: workerSession)
                }
            }
        }

        let phase3Duration = Date().timeIntervalSince(phase3Start)
        let stats = context.getStatistics()
        printFlush("")
        printFlush("Phase 3 Summary: processed=\(stats.processed), relevant=\(stats.relevant)")
        printFlush("⏱️ Phase 3 total: \(String(format: "%.1f", phase3Duration))s")
    }

    private func worker(id: Int, context: CrawlContext, session workerSession: LanguageModelSession) async {
        while let url = context.dequeueURL() {
            // Process until dequeueURL() returns nil
            // (isSufficient/maxURLs/empty queue checks are performed atomically in dequeueURL)

            let pageStart = Date()
            let host = url.host ?? url.absoluteString
            printFlush("   [W\(id)] → \(host)")

            sendProgress(.urlProcessingStarted(url: url))

            let result = await fetchAndReview(url: url, context: context, session: workerSession)

            context.completeURL(url)

            let pageDuration = Date().timeIntervalSince(pageStart)

            if let result = result {
                context.addResult(result.reviewed)

                // Send progress update for processed URL
                let processResult = URLProcessResult(
                    url: url,
                    title: result.reviewed.title,
                    extractedInfo: result.reviewed.extractedInfo,
                    isRelevant: result.reviewed.isRelevant,
                    duration: pageDuration,
                    status: .success
                )
                sendProgress(.urlProcessed(result: processResult))

                // Add deep crawl URLs to queue
                if let deepURLs = result.deepURLs, !deepURLs.isEmpty {
                    context.enqueueURLs(deepURLs)
                    printFlush("   [W\(id)]    +\(deepURLs.count) deep URLs")
                }

                let status = result.reviewed.isRelevant ? "✓" : "·"
                let info = result.reviewed.extractedInfo.prefix(60)
                printFlush("   [W\(id)] \(status) \(String(format: "%.1fs", pageDuration)) \(info)...")
            } else {
                // Send progress update for failed URL
                let processResult = URLProcessResult(
                    url: url,
                    title: nil,
                    extractedInfo: "",
                    isRelevant: false,
                    duration: pageDuration,
                    status: .failed
                )
                sendProgress(.urlProcessed(result: processResult))
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

    /// Fetch result containing the Remark and links, or error information.
    private enum FetchResult {
        case success(remark: Remark, links: [Link])
        case failure(errorType: FetchErrorType, error: Error)
    }

    /// Attempts to fetch content from a URL with a timeout.
    private func attemptFetch(url: URL) async -> FetchResult {
        do {
            let remark = try await withThrowingTaskGroup(of: Remark.self) { group in
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
            let links = try remark.extractLinks()
            return .success(remark: remark, links: links)
        } catch {
            let errorType = classifyFetchError(error)
            return .failure(errorType: errorType, error: error)
        }
    }

    private func fetchAndReview(url: URL, context: CrawlContext, session workerSession: LanguageModelSession) async -> FetchReviewResult? {
        let fetchStart = Date()
        let remark: Remark
        let links: [Link]

        // Retry configuration
        let maxRetries = 2
        var lastErrorType: FetchErrorType = .unknown

        // Attempt fetch with retries
        for attempt in 0...maxRetries {
            if attempt > 0 {
                // Exponential backoff: 1s, 2s, 4s
                let delay = Double(1 << (attempt - 1))
                printFlush("   ↻ Retry \(attempt)/\(maxRetries) after \(String(format: "%.0f", delay))s delay")
                try? await Task.sleep(for: .seconds(delay))
            }

            let result = await attemptFetch(url: url)

            switch result {
            case .success(let fetchedRemark, let fetchedLinks):
                remark = fetchedRemark
                links = fetchedLinks
                // Successfully fetched, continue to review
                let fetchDuration = Date().timeIntervalSince(fetchStart)
                return await processFetchedContent(
                    remark: remark,
                    links: links,
                    url: url,
                    context: context,
                    session: workerSession,
                    fetchDuration: fetchDuration
                )

            case .failure(let errorType, let error):
                lastErrorType = errorType

                // Only retry if error is retryable and we haven't exhausted retries
                if errorType.isRetryable && attempt < maxRetries {
                    if verbose {
                        printFlush("   ⚠️ Fetch failed (\(errorType.description)), will retry: \(url.host ?? url.absoluteString)")
                    }
                    continue
                } else {
                    // Final failure - log with error type
                    printFlush("   ✗ Fetch failed (\(errorType.description)): \(url.host ?? url.absoluteString)")
                    if verbose {
                        printFlush("      Error: \(error)")
                    }
                    return nil
                }
            }
        }

        // Should not reach here, but just in case
        printFlush("   ✗ Fetch exhausted retries (\(lastErrorType.description)): \(url.host ?? url.absoluteString)")
        return nil
    }

    /// Process fetched content through LLM review.
    private func processFetchedContent(
        remark: Remark,
        links: [Link],
        url: URL,
        context: CrawlContext,
        session workerSession: LanguageModelSession,
        fetchDuration: TimeInterval
    ) async -> FetchReviewResult? {

        // Store full markdown for use in Phase 5
        context.storePageContent(url: url, markdown: remark.markdown)

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
            relevantDomains: relevantDomains,
            session: workerSession
        )
        let llmDuration = Date().timeIntervalSince(llmStart)

        // Extract excerpts from relevantRanges
        let markdownLines = remark.markdown.components(separatedBy: "\n")
        let excerpts = review.relevantRanges.compactMap { range -> String? in
            let safeStart = max(0, range.lowerBound)
            let safeEnd = min(markdownLines.count, range.upperBound)
            guard safeStart < safeEnd else { return nil }
            return markdownLines[safeStart..<safeEnd].joined(separator: "\n")
        }

        let reviewed = ReviewedContent(
            url: url,
            title: remark.title.isEmpty ? nil : remark.title,
            extractedInfo: review.extractedInfo,
            isRelevant: review.isRelevant,
            relevantRanges: review.relevantRanges,
            excerpts: excerpts
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
        relevantDomains: Set<String>,
        session workerSession: LanguageModelSession
    ) async -> ContentReview {
        let maxChars = configuration.researchConfiguration.contentMaxChars

        // Add line numbers to markdown for relevantRanges extraction
        let lines = markdown.components(separatedBy: "\n")
        let numberedLines = lines.enumerated().map { index, line in
            "\(index): \(line)"
        }
        let numberedContent = numberedLines.joined(separator: "\n")
        let truncatedContent = String(numberedContent.prefix(maxChars))

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

        ## ページ: \(title)（行番号付き）
        \(truncatedContent)

        ## リンク
        \(linksInfo)

        ## 出力
        - isRelevant: 新しい関連情報があるか
        - extractedInfo: 関連情報の要約（100-150字、既知と重複しない）
        - shouldDeepCrawl: 深掘りすべきか
        - priorityLinks: 深掘り候補のリンク
        - relevantRanges: 関連情報が含まれる行範囲（start: 開始行, end: 終了行）
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
            let response = try await workerSession.respond(generating: ContentReviewResponse.self) {
                Prompt(prompt)
            }

            if verbose {
                printFlush("    ┌─── LLM OUTPUT (ContentReview) ───")
                printFlush("    isRelevant: \(response.content.isRelevant)")
                printFlush("    extractedInfo: \(response.content.extractedInfo)")
                printFlush("    shouldDeepCrawl: \(response.content.shouldDeepCrawl)")
                printFlush("    priorityLinks: \(response.content.priorityLinks.count) items")
                printFlush("    relevantRanges: \(response.content.relevantRanges.map { "\($0.start)..<\($0.end)" })")
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
        収集した情報の完全性を分析し、情報ギャップを特定してください。

        ## 目的
        \(context.objective)

        ## 現在の成功基準
        \(criteriaList)

        ## 検索履歴
        - 検索ラウンド: \(searchRoundNumber)回目
        - このラウンドで見つかった新規関連ページ: \(newRelevantThisRound)件
        - 累計関連ページ: \(context.relevantCount)件

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

        if verbose {
            printFlush("┌─── LLM INPUT (SufficiencyCheck) ───")
            printFlush("objective: \(context.objective)")
            printFlush("successCriteria: \(context.successCriteria)")
            printFlush("searchRound: \(searchRoundNumber), newRelevantThisRound: \(newRelevantThisRound)")
            printFlush("collectedInfo: \(reviewedContents.count) items")
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        sendProgress(.promptSent(phase: "Phase 4: Sufficiency Check", prompt: prompt))

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
        relevantExcerpts: [CrawlContext.PageExcerpt],
        reviewedContents: [ReviewedContent],
        objective: String,
        questions: [String]
    ) async -> String {
        let relevantContents = reviewedContents.filter { $0.isRelevant }

        guard !relevantContents.isEmpty else {
            return "# \(objective)\n\n関連情報を収集できませんでした。"
        }

        // Build context from relevant excerpts (actual page content, not just summaries)
        var contextSection = ""
        for excerpt in relevantExcerpts {
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

        let questionsSection = questions.isEmpty ? "" : """

        ## 回答すべき具体的な質問
        \(questions.map { "- \($0)" }.joined(separator: "\n"))
        """

        let prompt = """
        あなたは調査結果を報告する専門家です。

        ## ユーザーの問い
        \(objective)
        \(questionsSection)

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

        if verbose {
            printFlush("┌─── LLM INPUT (FinalResponse) ───")
            printFlush("objective: \(objective)")
            printFlush("questions: \(questions)")
            printFlush("relevantExcerpts: \(relevantExcerpts.count) pages")
            printFlush("contextSection: \(contextSection.count) chars")
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        sendProgress(.promptSent(phase: "Phase 5: Response Building", prompt: prompt))

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
            fallback += contextSection
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
