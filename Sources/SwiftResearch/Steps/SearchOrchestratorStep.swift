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

        // ===== Phase 0: Initial Search =====
        printFlush("═══════════════════════════════════════════")
        printFlush("🔎 Phase 0: INITIAL SEARCH")
        printFlush("═══════════════════════════════════════════")
        sendProgress(.phaseChanged(phase: .initialSearch))
        let phase0Start = Date()

        // Disambiguate query using domain context before searching
        let searchQuery: String
        if configuration.domainContext != nil {
            do {
                searchQuery = try await CrawlerConfigurationContext.withValue(configuration) {
                    try await QueryDisambiguationStep()
                        .session(session)
                        .run(QueryDisambiguationInput(query: input.objective, verbose: verbose))
                }
                if searchQuery != input.objective {
                    printFlush("🔍 Searching: \(searchQuery) (disambiguated from: \(input.objective))")
                } else {
                    printFlush("🔍 Searching: \(searchQuery)")
                }
            } catch {
                printFlush("⚠️ Query disambiguation failed: \(error), using original")
                searchQuery = input.objective
            }
        } else {
            searchQuery = input.objective
            printFlush("🔍 Searching: \(searchQuery)")
        }

        let initialSearchResult = await performInitialSearch(query: searchQuery)

        let phase0Duration = Date().timeIntervalSince(phase0Start)
        printFlush("⏱️ Phase 0 duration: \(String(format: "%.1f", phase0Duration))s")
        if let info = initialSearchResult.summary {
            printFlush("Background info: \(info.prefix(200))...")
        } else {
            printFlush("No background info found (continuing without)")
        }
        printFlush("")

        // ===== Phase 1: Objective Analysis =====
        printFlush("═══════════════════════════════════════════")
        printFlush("📊 Phase 1: OBJECTIVE ANALYSIS")
        printFlush("═══════════════════════════════════════════")
        sendProgress(.phaseChanged(phase: .analyzing))
        let phase1Start = Date()

        let analysisInput = ObjectiveAnalysisInput(
            objective: input.objective,
            backgroundInfo: initialSearchResult.summary,
            verbose: verbose
        )
        let analysis = try await ObjectiveAnalysisStep(progressContinuation: progressContinuation)
            .session(session)
            .run(analysisInput)

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

        // Register Phase 0 visited URLs to avoid re-visiting
        for url in initialSearchResult.visitedURLs {
            context.enqueueURLs([url])
            _ = context.dequeueURL()
            context.completeURL(url)
        }

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

            let sufficiencyInput = SufficiencyCheckInput(
                objective: context.objective,
                successCriteria: context.successCriteria,
                reviewedContents: context.reviewedContents,
                relevantCount: context.relevantCount,
                searchRoundNumber: usedKeywords.count,
                newRelevantThisRound: newRelevantThisRound,
                verbose: verbose
            )
            let sufficiency = try await SufficiencyCheckStep(progressContinuation: progressContinuation)
                .session(session)
                .run(sufficiencyInput)

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

        let responseBuildingInput = ResponseBuildingInput(
            relevantExcerpts: relevantExcerpts,
            reviewedContents: reviewedContents,
            objective: input.objective,
            questions: analysis.questions,
            successCriteria: context.successCriteria,
            verbose: verbose
        )
        let responseMarkdown = try await ResponseBuildingStep(progressContinuation: progressContinuation)
            .session(session)
            .run(responseBuildingInput)

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

    // MARK: - Phase 0: Initial Search

    /// Result of initial search containing summary and visited URLs.
    private struct InitialSearchResult: Sendable {
        let summary: String?
        let visitedURLs: [URL]
    }

    /// Performs initial search to gather background information about the query.
    private func performInitialSearch(query: String) async -> InitialSearchResult {
        let searchStep = SearchStep(
            searchEngine: configuration.searchEngine,
            blockedDomains: configuration.blockedDomains
        )

        let urls: [URL]
        do {
            urls = try await searchStep.run(KeywordSearchInput(keyword: query))
        } catch {
            printFlush("⚠️ Initial search failed: \(error)")
            return InitialSearchResult(summary: nil, visitedURLs: [])
        }

        let topURLs = Array(urls.filter { isAllowedDomain($0) }.prefix(2))
        var summaries: [String] = []
        var visitedURLs: [URL] = []

        for url in topURLs {
            visitedURLs.append(url)
            do {
                let remark = try await withThrowingTaskGroup(of: Remark.self) { group in
                    group.addTask {
                        try await Remark.fetch(from: url)
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(10))
                        throw CancellationError()
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }

                if let summary = await extractBasicInfo(markdown: remark.markdown, query: query) {
                    summaries.append("【\(url.host ?? url.absoluteString)】\(summary)")
                }
            } catch {
                printFlush("⚠️ Failed to fetch \(url.host ?? ""): \(error)")
            }
        }

        let summary = summaries.isEmpty ? nil : summaries.joined(separator: "\n\n")
        return InitialSearchResult(summary: summary, visitedURLs: visitedURLs)
    }

    /// Extracts basic information from markdown content.
    private func extractBasicInfo(markdown: String, query: String) async -> String? {
        let truncated = String(markdown.prefix(3000))

        let domainSection = configuration.domainContext.map { context in
            """

            ## Domain Context
            \(context)
            Interpret the query from this domain's perspective.
            """
        } ?? ""

        let prompt = """
        Extract basic information about "\(query)" from the following page.
        Provide a concise summary (100-200 characters).
        \(domainSection)

        \(truncated)
        """

        do {
            let response = try await session.respond {
                Prompt(prompt)
            }
            return response.content
        } catch {
            return nil
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
                    // Use TaskLocal directly for implicit propagation to worker
                    await SessionContext.$current.withValue(workerSession) {
                        await CrawlerConfigurationContext.withValue(self.configuration) {
                            await self.worker(id: workerID, context: context)
                        }
                    }
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

            sendProgress(.urlProcessingStarted(url: url))

            let result = await fetchAndReview(url: url, context: context)

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

    private func fetchAndReview(url: URL, context: CrawlContext) async -> FetchReviewResult? {
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

    /// Process fetched content through LLM review using ContentReviewStep.
    private func processFetchedContent(
        remark: Remark,
        links: [Link],
        url: URL,
        context: CrawlContext,
        fetchDuration: TimeInterval
    ) async -> FetchReviewResult? {

        // Store full markdown for use in Phase 5
        context.storePageContent(url: url, markdown: remark.markdown)

        // Get known facts to improve review accuracy
        let knownFacts = context.getKnownFacts()
        let relevantDomains = context.getRelevantDomains()

        // Review using ContentReviewStep (uses @Session and @Context implicitly)
        let llmStart = Date()
        let reviewInput = ContentReviewInput(
            markdown: remark.markdown,
            title: remark.title,
            links: links,
            sourceURL: url,
            objective: context.objective,
            knownFacts: knownFacts,
            relevantDomains: relevantDomains,
            verbose: verbose
        )
        let review: ContentReview
        do {
            review = try await ContentReviewStep().run(reviewInput)
        } catch {
            if verbose {
                printFlush("   ⚠️ Review failed: \(error)")
            }
            review = ContentReview.irrelevant()
        }
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
