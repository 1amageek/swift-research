import Foundation

// MARK: - CrawlCandidate

/// A URL candidate for crawling with priority score.
///
/// Candidates are prioritized by their score for efficient crawling.
/// Higher scores indicate higher relevance to the research objective.
///
/// ## Topics
///
/// ### Properties
/// - ``url``
/// - ``score``
/// - ``title``
/// - ``reason``
/// - ``sourceURL``
/// - ``addedAt``
public struct CrawlCandidate: Sendable, Comparable {
    /// The URL to crawl.
    public let url: URL

    /// Priority score between 0.0 and 1.0. Higher values indicate higher priority.
    public let score: Double

    /// The link title, if available.
    public let title: String?

    /// The reason for the assigned score.
    public let reason: String?

    /// The URL of the page where this link was discovered.
    public let sourceURL: URL?

    /// The timestamp when this candidate was added.
    public let addedAt: Date

    /// Creates a new crawl candidate.
    ///
    /// - Parameters:
    ///   - url: The URL to crawl.
    ///   - score: Priority score (0.0-1.0). Values outside this range are clamped.
    ///   - title: The link title, if available.
    ///   - reason: The reason for the assigned score.
    ///   - sourceURL: The URL where this link was discovered.
    public init(
        url: URL,
        score: Double,
        title: String? = nil,
        reason: String? = nil,
        sourceURL: URL? = nil
    ) {
        self.url = url
        self.score = min(1.0, max(0.0, score))
        self.title = title
        self.reason = reason
        self.sourceURL = sourceURL
        self.addedAt = Date()
    }

    /// Compares candidates by score. Higher scores are considered "less than" for priority queue ordering.
    public static func < (lhs: CrawlCandidate, rhs: CrawlCandidate) -> Bool {
        lhs.score > rhs.score
    }
}

// MARK: - Hashable

extension CrawlCandidate: Hashable {
    public static func == (lhs: CrawlCandidate, rhs: CrawlCandidate) -> Bool {
        lhs.url == rhs.url
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

// MARK: - CrawlCandidateStack

/// A priority-ordered stack of crawl candidates.
///
/// This actor maintains a sorted list of candidates, with higher-scored candidates
/// appearing first. Duplicate URLs are automatically rejected.
///
/// ## Topics
///
/// ### Adding Candidates
/// - ``push(_:)-7x1qk``
/// - ``push(_:)-5qr7l``
///
/// ### Retrieving Candidates
/// - ``pop()``
/// - ``pop(count:)``
/// - ``peek(count:)``
///
/// ### Inspection
/// - ``contains(_:)``
/// - ``count``
/// - ``isEmpty``
public actor CrawlCandidateStack {

    private var candidates: [CrawlCandidate] = []
    private var urlSet: Set<URL> = []

    /// Creates an empty candidate stack.
    public init() {}

    /// Adds a candidate to the stack, maintaining priority order.
    ///
    /// Duplicate URLs are silently ignored.
    ///
    /// - Parameter candidate: The candidate to add.
    public func push(_ candidate: CrawlCandidate) {
        guard !urlSet.contains(candidate.url) else { return }
        urlSet.insert(candidate.url)
        candidates.append(candidate)
        candidates.sort()
    }

    /// Adds multiple candidates to the stack.
    ///
    /// Duplicate URLs are silently ignored.
    ///
    /// - Parameter newCandidates: The candidates to add.
    public func push(_ newCandidates: [CrawlCandidate]) {
        for candidate in newCandidates {
            if !urlSet.contains(candidate.url) {
                urlSet.insert(candidate.url)
                candidates.append(candidate)
            }
        }
        candidates.sort()
    }

    /// Removes and returns the highest-priority candidate.
    ///
    /// - Returns: The highest-priority candidate, or `nil` if the stack is empty.
    public func pop() -> CrawlCandidate? {
        guard !candidates.isEmpty else { return nil }
        let candidate = candidates.removeFirst()
        urlSet.remove(candidate.url)
        return candidate
    }

    /// Removes and returns the top N highest-priority candidates.
    ///
    /// Useful for parallel processing of multiple candidates.
    ///
    /// - Parameter count: The maximum number of candidates to retrieve.
    /// - Returns: An array of candidates, up to the specified count.
    public func pop(count: Int) -> [CrawlCandidate] {
        let n = min(count, candidates.count)
        guard n > 0 else { return [] }

        let result = Array(candidates.prefix(n))
        candidates.removeFirst(n)
        for candidate in result {
            urlSet.remove(candidate.url)
        }
        return result
    }

    /// Returns the top N highest-priority candidates without removing them.
    ///
    /// - Parameter count: The maximum number of candidates to peek.
    /// - Returns: An array of candidates, up to the specified count.
    public func peek(count: Int) -> [CrawlCandidate] {
        Array(candidates.prefix(count))
    }

    /// Checks whether a URL exists in the stack.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL is in the stack.
    public func contains(_ url: URL) -> Bool {
        urlSet.contains(url)
    }

    /// The number of candidates in the stack.
    public var count: Int { candidates.count }

    /// Whether the stack is empty.
    public var isEmpty: Bool { candidates.isEmpty }

    /// Removes all candidates from the stack.
    public func clear() {
        candidates.removeAll()
        urlSet.removeAll()
    }
}
