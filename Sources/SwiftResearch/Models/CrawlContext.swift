import Foundation

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
public final class CrawlContext: @unchecked Sendable {
    private let lock = NSLock()

    // MARK: - URL Management

    private var _urlQueue: [URL] = []
    private var _visited: Set<URL> = []
    private var _inProgress: Set<URL> = []

    // MARK: - Collected Information

    private var _reviewedContents: [ReviewedContent] = []
    private var _extractedFacts: [String] = []
    private var _relevantDomains: [String: Int] = [:]

    // MARK: - Objective

    /// The research objective describing what information to find.
    public let objective: String

    /// Criteria that determine when sufficient information has been collected.
    public let successCriteria: [String]

    // MARK: - Control

    private var _isSufficient: Bool = false
    private var _totalProcessed: Int = 0
    private let _maxURLs: Int

    // MARK: - Configuration

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
        self.successCriteria = successCriteria
        self._maxURLs = maxURLs ?? configuration.maxURLs
        self.configuration = configuration
    }

    // MARK: - URL Queue Operations

    /// Adds URLs to the queue, automatically filtering duplicates.
    ///
    /// URLs that have already been visited or are in the queue are ignored.
    ///
    /// - Parameter urls: The URLs to enqueue.
    public func enqueueURLs(_ urls: [URL]) {
        lock.lock()
        defer { lock.unlock() }
        for url in urls where !_visited.contains(url) {
            _visited.insert(url)
            _urlQueue.append(url)
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
        lock.lock()
        defer { lock.unlock() }
        guard !_isSufficient,
              _totalProcessed + _inProgress.count < _maxURLs,
              !_urlQueue.isEmpty else { return nil }
        let url = _urlQueue.removeFirst()
        _inProgress.insert(url)
        return url
    }

    /// Marks a URL as processed.
    ///
    /// Call this after successfully processing a URL obtained from ``dequeueURL()``.
    ///
    /// - Parameter url: The URL that was processed.
    public func completeURL(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        _inProgress.remove(url)
        _totalProcessed += 1
    }

    /// Checks whether a URL has been visited.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL has been visited or is queued.
    public func isVisited(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _visited.contains(url)
    }

    // MARK: - Results Operations

    /// Adds a reviewed content result.
    ///
    /// If the content is relevant, its extracted information is added to
    /// the known facts pool and the domain is tracked.
    ///
    /// - Parameter content: The reviewed content to add.
    public func addResult(_ content: ReviewedContent) {
        lock.lock()
        defer { lock.unlock() }
        _reviewedContents.append(content)
        if content.isRelevant {
            _extractedFacts.append(content.extractedInfo)
            if let host = content.url.host {
                _relevantDomains[host, default: 0] += 1
            }
        }
    }

    /// All reviewed contents collected so far.
    public var reviewedContents: [ReviewedContent] {
        lock.lock()
        defer { lock.unlock() }
        return _reviewedContents
    }

    /// The number of relevant pages found.
    public var relevantCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _reviewedContents.filter { $0.isRelevant }.count
    }

    // MARK: - Shared Information

    /// Returns recently extracted facts for improving review accuracy.
    ///
    /// Workers can use these facts to avoid extracting duplicate information.
    ///
    /// - Parameter limit: Maximum facts to return. Defaults to configuration value.
    /// - Returns: The most recent extracted facts.
    public func getKnownFacts(limit: Int? = nil) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let effectiveLimit = limit ?? configuration.knownFactsLimit
        return Array(_extractedFacts.suffix(effectiveLimit))
    }

    /// Returns domains that have yielded multiple relevant pages.
    ///
    /// These domains may be prioritized for deep crawling.
    ///
    /// - Returns: Set of domain names with 2+ relevant pages.
    public func getRelevantDomains() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(_relevantDomains.filter { $0.value >= 2 }.keys)
    }

    // MARK: - Control

    /// Marks the crawl as having sufficient information.
    ///
    /// After calling this method, ``dequeueURL()`` will return `nil`
    /// and all workers will stop processing.
    public func markSufficient() {
        lock.lock()
        defer { lock.unlock() }
        _isSufficient = true
        _urlQueue.removeAll()
    }

    /// Whether sufficient information has been collected.
    public var isSufficient: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isSufficient
    }

    /// The total number of URLs that have been processed.
    public var totalProcessed: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalProcessed
    }

    /// Whether there are more URLs to process.
    ///
    /// Returns `true` if the queue is non-empty or URLs are in progress.
    public var hasMoreURLs: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_urlQueue.isEmpty || !_inProgress.isEmpty
    }

    /// The number of URLs currently in the queue.
    public var queueCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _urlQueue.count
    }

    /// The number of URLs that have been visited or queued.
    public var visitedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _visited.count
    }

    /// The maximum number of URLs to process.
    public var maxURLs: Int {
        _maxURLs
    }

    // MARK: - Statistics

    /// Returns current crawl statistics.
    ///
    /// - Returns: A tuple containing processed, relevant, queued, and in-progress counts.
    public func getStatistics() -> (processed: Int, relevant: Int, queued: Int, inProgress: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (
            processed: _totalProcessed,
            relevant: _reviewedContents.filter { $0.isRelevant }.count,
            queued: _urlQueue.count,
            inProgress: _inProgress.count
        )
    }
}
