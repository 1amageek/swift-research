import Foundation
import Synchronization

/// Thread-safe shared state for parallel crawling operations.
///
/// `CrawlContext` manages the URL queue, visited URLs, and collected results
/// across multiple concurrent workers. All public methods are thread-safe.
///
/// ## Overview
///
/// Workers dequeue URLs using ``dequeueURL()``, process them, and mark completion
/// with ``completeURL(_:)``. The context automatically tracks statistics and
/// enforces URL limits.
///
/// ## Example
///
/// ```swift
/// let context = CrawlContext(
///     objective: "Research Swift concurrency",
///     successCriteria: ["Find official documentation"]
/// )
///
/// // Add URLs to the queue
/// context.enqueueURLs(urls)
///
/// // Worker loop
/// while let url = context.dequeueURL() {
///     // Process URL...
///     context.completeURL(url)
/// }
/// ```
public final class CrawlContext: Sendable {

    // MARK: - State

    private struct State: Sendable {
        var urlQueue: [URL] = []
        var visited: Set<URL> = []
        var inProgress: Set<URL> = []
        var reviewedContents: [ReviewedContent] = []
        var extractedFacts: [String] = []
        var relevantDomains: [String: Int] = [:]
        var pageContents: [URL: String] = [:]
        var successCriteria: [String]
        var isSufficient: Bool = false
        var totalProcessed: Int = 0
    }

    private let state: Mutex<State>

    // MARK: - Immutable Properties

    /// The research objective describing what information to find.
    public let objective: String

    /// The maximum number of URLs to process.
    public let maxURLs: Int

    /// The configuration used for this crawl context.
    public let configuration: ResearchConfiguration

    /// Maximum number of concurrent workers.
    public var maxConcurrent: Int { configuration.maxConcurrent }

    /// Maximum number of known facts to share with workers.
    public var knownFactsLimit: Int { configuration.knownFactsLimit }

    /// Creates a new crawl context.
    ///
    /// - Parameters:
    ///   - objective: The research objective.
    ///   - successCriteria: Criteria for determining sufficient information.
    ///   - maxURLs: Maximum URLs to process. Defaults to configuration value.
    ///   - configuration: The research configuration to use.
    public init(
        objective: String,
        successCriteria: [String],
        maxURLs: Int? = nil,
        configuration: ResearchConfiguration = .shared
    ) {
        self.objective = objective
        self.maxURLs = maxURLs ?? configuration.maxURLs
        self.configuration = configuration
        self.state = Mutex(State(successCriteria: successCriteria))
    }

    // MARK: - Success Criteria

    /// Criteria that determine when sufficient information has been collected.
    public var successCriteria: [String] {
        state.withLock { $0.successCriteria }
    }

    /// Updates the success criteria.
    ///
    /// This completely replaces the current criteria with the new ones.
    /// Called after Phase 4 with the LLM's updated criteria list.
    ///
    /// - Parameter newCriteria: The new success criteria to use.
    public func updateSuccessCriteria(_ newCriteria: [String]) {
        guard !newCriteria.isEmpty else { return }
        state.withLock { $0.successCriteria = newCriteria }
    }

    // MARK: - URL Queue Operations

    /// Adds URLs to the queue, automatically filtering duplicates.
    ///
    /// URLs that have already been visited or are in the queue are ignored.
    ///
    /// - Parameter urls: The URLs to enqueue.
    public func enqueueURLs(_ urls: [URL]) {
        state.withLock { state in
            for url in urls where !state.visited.contains(url) {
                state.visited.insert(url)
                state.urlQueue.append(url)
            }
        }
    }

    /// Dequeues the next URL for processing.
    ///
    /// Returns `nil` when:
    /// - The queue is empty
    /// - The sufficient flag is set
    /// - The URL limit has been reached (including in-progress URLs)
    ///
    /// The in-progress count is included in the limit check to prevent
    /// exceeding `maxURLs` during parallel execution.
    ///
    /// - Returns: The next URL to process, or `nil` if none available.
    public func dequeueURL() -> URL? {
        state.withLock { state in
            guard !state.isSufficient,
                  state.totalProcessed + state.inProgress.count < maxURLs,
                  !state.urlQueue.isEmpty else { return nil }
            let url = state.urlQueue.removeFirst()
            state.inProgress.insert(url)
            return url
        }
    }

    /// Marks a URL as processed.
    ///
    /// Call this after successfully processing a URL obtained from ``dequeueURL()``.
    ///
    /// - Parameter url: The URL that was processed.
    public func completeURL(_ url: URL) {
        state.withLock { state in
            state.inProgress.remove(url)
            state.totalProcessed += 1
        }
    }

    /// Checks whether a URL has been visited.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL has been visited or is queued.
    public func isVisited(_ url: URL) -> Bool {
        state.withLock { $0.visited.contains(url) }
    }

    // MARK: - Results Operations

    /// Adds a reviewed content result.
    ///
    /// If the content is relevant, its extracted information is added to
    /// the known facts pool and the domain is tracked.
    ///
    /// - Parameter content: The reviewed content to add.
    public func addResult(_ content: ReviewedContent) {
        state.withLock { state in
            state.reviewedContents.append(content)
            if content.isRelevant {
                state.extractedFacts.append(content.extractedInfo)
                if let host = content.url.host {
                    state.relevantDomains[host, default: 0] += 1
                }
            }
        }
    }

    /// All reviewed contents collected so far.
    public var reviewedContents: [ReviewedContent] {
        state.withLock { $0.reviewedContents }
    }

    /// The number of relevant pages found.
    public var relevantCount: Int {
        state.withLock { $0.reviewedContents.filter { $0.isRelevant }.count }
    }

    // MARK: - Shared Information

    /// Returns recently extracted facts for improving review accuracy.
    ///
    /// Workers can use these facts to avoid extracting duplicate information.
    ///
    /// - Parameter limit: Maximum facts to return. Defaults to configuration value.
    /// - Returns: The most recent extracted facts.
    public func getKnownFacts(limit: Int? = nil) -> [String] {
        let effectiveLimit = limit ?? configuration.knownFactsLimit
        return state.withLock { Array($0.extractedFacts.suffix(effectiveLimit)) }
    }

    /// Returns domains that have yielded multiple relevant pages.
    ///
    /// These domains may be prioritized for deep crawling.
    ///
    /// - Returns: Set of domain names with 2+ relevant pages.
    public func getRelevantDomains() -> Set<String> {
        state.withLock { Set($0.relevantDomains.filter { $0.value >= 2 }.keys) }
    }

    // MARK: - Page Contents

    /// Stores the full markdown content of a page.
    ///
    /// - Parameters:
    ///   - url: The URL of the page.
    ///   - markdown: The full markdown content.
    public func storePageContent(url: URL, markdown: String) {
        state.withLock { $0.pageContents[url] = markdown }
    }

    /// Retrieves the stored markdown content for a URL.
    ///
    /// - Parameter url: The URL to look up.
    /// - Returns: The stored markdown content, or `nil` if not found.
    public func getPageContent(url: URL) -> String? {
        state.withLock { $0.pageContents[url] }
    }

    /// Represents extracted context from a relevant page.
    public struct PageExcerpt: Sendable {
        public let url: URL
        public let title: String?
        public let excerpts: [String]
    }

    /// Returns excerpts from relevant pages based on their line ranges.
    ///
    /// For each relevant page, extracts only the lines specified in `relevantRanges`.
    ///
    /// - Returns: Array of page excerpts containing only relevant portions.
    public func getRelevantContext() -> [PageExcerpt] {
        state.withLock { state in
            var result: [PageExcerpt] = []

            for content in state.reviewedContents where content.isRelevant {
                guard let markdown = state.pageContents[content.url] else { continue }
                let lines = markdown.components(separatedBy: "\n")

                var excerpts: [String] = []
                for range in content.relevantRanges {
                    let safeStart = max(0, range.lowerBound)
                    let safeEnd = min(lines.count, range.upperBound)
                    if safeStart < safeEnd {
                        let excerpt = lines[safeStart..<safeEnd].joined(separator: "\n")
                        excerpts.append(excerpt)
                    }
                }

                if !excerpts.isEmpty {
                    result.append(PageExcerpt(url: content.url, title: content.title, excerpts: excerpts))
                }
            }

            return result
        }
    }

    // MARK: - Control

    /// Marks the crawl as having sufficient information.
    ///
    /// After calling this method, ``dequeueURL()`` will return `nil`
    /// and all workers will stop processing.
    public func markSufficient() {
        state.withLock { state in
            state.isSufficient = true
            state.urlQueue.removeAll()
        }
    }

    /// Whether sufficient information has been collected.
    public var isSufficient: Bool {
        state.withLock { $0.isSufficient }
    }

    /// The total number of URLs that have been processed.
    public var totalProcessed: Int {
        state.withLock { $0.totalProcessed }
    }

    /// Whether there are more URLs to process.
    ///
    /// Returns `true` if the queue is non-empty or URLs are in progress.
    public var hasMoreURLs: Bool {
        state.withLock { !$0.urlQueue.isEmpty || !$0.inProgress.isEmpty }
    }

    /// The number of URLs currently in the queue.
    public var queueCount: Int {
        state.withLock { $0.urlQueue.count }
    }

    /// The number of URLs that have been visited or queued.
    public var visitedCount: Int {
        state.withLock { $0.visited.count }
    }

    // MARK: - Statistics

    /// Returns current crawl statistics.
    ///
    /// - Returns: A tuple containing processed, relevant, queued, and in-progress counts.
    public func getStatistics() -> (processed: Int, relevant: Int, queued: Int, inProgress: Int) {
        state.withLock { state in
            (
                processed: state.totalProcessed,
                relevant: state.reviewedContents.filter { $0.isRelevant }.count,
                queued: state.urlQueue.count,
                inProgress: state.inProgress.count
            )
        }
    }
}
