import Foundation

// MARK: - MemoryStorage

/// An in-memory storage for crawled content.
///
/// This actor provides thread-safe storage for crawled web pages,
/// with support for URL tracking, searching, and aggregation.
///
/// ## Topics
///
/// ### Storage Operations
/// - ``store(_:)-4z5gq``
/// - ``store(_:)-7gq4l``
/// - ``get(by:)-5z8ms``
/// - ``get(by:)-2k5vq``
/// - ``getAll()``
///
/// ### URL Tracking
/// - ``hasVisited(_:)``
/// - ``markAsVisited(_:)``
/// - ``getVisitedURLs()``
///
/// ### Statistics
/// - ``count``
/// - ``visitedCount``
/// - ``totalLinksCount``
///
/// ### Search
/// - ``search(titleContaining:)``
/// - ``search(contentContaining:)``
/// - ``getContents(forDomain:)``
///
/// ### Aggregation
/// - ``getCombinedMarkdown(separator:)``
/// - ``getContentForSummary(maxCharacters:)``
///
/// ### Management
/// - ``remove(by:)-3eqjz``
/// - ``remove(by:)-7zzoh``
/// - ``clear()``
/// - ``removeContents(olderThan:)``
public actor MemoryStorage {

    // MARK: - Properties

    private var contents: [UUID: CrawledContent] = [:]
    private var urlIndex: [URL: UUID] = [:]
    private var visitedURLs: Set<URL> = []

    // MARK: - Initialization

    /// Creates an empty memory storage.
    public init() {}

    // MARK: - Storage Operations

    /// Stores content in the storage.
    ///
    /// - Parameter content: The content to store.
    public func store(_ content: CrawledContent) {
        contents[content.id] = content
        urlIndex[content.url] = content.id
        visitedURLs.insert(content.url)
    }

    /// Stores multiple content items.
    ///
    /// - Parameter newContents: The content items to store.
    public func store(_ newContents: [CrawledContent]) {
        for content in newContents {
            store(content)
        }
    }

    /// Retrieves content by its ID.
    ///
    /// - Parameter id: The content ID.
    /// - Returns: The content, or `nil` if not found.
    public func get(by id: UUID) -> CrawledContent? {
        contents[id]
    }

    /// Retrieves content by its URL.
    ///
    /// - Parameter url: The content URL.
    /// - Returns: The content, or `nil` if not found.
    public func get(by url: URL) -> CrawledContent? {
        guard let id = urlIndex[url] else { return nil }
        return contents[id]
    }

    /// Retrieves all stored content, sorted by crawl time.
    ///
    /// - Returns: All content items, oldest first.
    public func getAll() -> [CrawledContent] {
        Array(contents.values).sorted { $0.crawledAt < $1.crawledAt }
    }

    // MARK: - URL Tracking

    /// Checks whether a URL has been visited.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL has been visited.
    public func hasVisited(_ url: URL) -> Bool {
        visitedURLs.contains(url)
    }

    /// Marks a URL as visited.
    ///
    /// - Parameter url: The URL to mark.
    public func markAsVisited(_ url: URL) {
        visitedURLs.insert(url)
    }

    /// Returns all visited URLs.
    ///
    /// - Returns: The set of visited URLs.
    public func getVisitedURLs() -> Set<URL> {
        visitedURLs
    }

    // MARK: - Statistics

    /// The number of stored content items.
    public var count: Int {
        contents.count
    }

    /// The number of visited URLs.
    public var visitedCount: Int {
        visitedURLs.count
    }

    /// The total number of links across all content.
    public var totalLinksCount: Int {
        contents.values.reduce(0) { $0 + $1.links.count }
    }

    // MARK: - Search

    /// Searches for content by title.
    ///
    /// - Parameter query: The search query (case-insensitive).
    /// - Returns: Content items with matching titles.
    public func search(titleContaining query: String) -> [CrawledContent] {
        let lowercasedQuery = query.lowercased()
        return contents.values.filter {
            $0.title?.lowercased().contains(lowercasedQuery) ?? false
        }
    }

    /// Searches for content by markdown content.
    ///
    /// - Parameter query: The search query (case-insensitive).
    /// - Returns: Content items with matching content.
    public func search(contentContaining query: String) -> [CrawledContent] {
        let lowercasedQuery = query.lowercased()
        return contents.values.filter {
            $0.markdown.lowercased().contains(lowercasedQuery)
        }
    }

    /// Retrieves content for a specific domain.
    ///
    /// - Parameter domain: The domain to filter by.
    /// - Returns: Content items from the specified domain.
    public func getContents(forDomain domain: String) -> [CrawledContent] {
        contents.values.filter {
            $0.url.host == domain
        }
    }

    // MARK: - Aggregation

    /// Combines all content into a single markdown string.
    ///
    /// - Parameter separator: The separator between content items.
    /// - Returns: Combined markdown content.
    public func getCombinedMarkdown(separator: String = "\n\n---\n\n") -> String {
        getAll()
            .map { content in
                var result = ""
                if let title = content.title {
                    result += "# \(title)\n\n"
                }
                result += "URL: \(content.url.absoluteString)\n\n"
                result += content.markdown
                return result
            }
            .joined(separator: separator)
    }

    /// Retrieves content for summarization with a character limit.
    ///
    /// Truncates individual content items to fit within the limit.
    ///
    /// - Parameter maxCharacters: The maximum total characters.
    /// - Returns: Combined content suitable for summarization.
    public func getContentForSummary(maxCharacters: Int = 50000) -> String {
        var result = ""
        for content in getAll() {
            let entry = """
            ## \(content.title ?? content.url.absoluteString)
            \(content.markdown.prefix(2000))

            """
            if result.count + entry.count > maxCharacters {
                break
            }
            result += entry
        }
        return result
    }

    // MARK: - Management

    /// Removes content by its ID.
    ///
    /// - Parameter id: The content ID to remove.
    public func remove(by id: UUID) {
        if let content = contents.removeValue(forKey: id) {
            urlIndex.removeValue(forKey: content.url)
        }
    }

    /// Removes content by its URL.
    ///
    /// Also removes the URL from the visited set.
    ///
    /// - Parameter url: The URL to remove.
    public func remove(by url: URL) {
        if let id = urlIndex.removeValue(forKey: url) {
            contents.removeValue(forKey: id)
        }
        visitedURLs.remove(url)
    }

    /// Clears all stored data.
    public func clear() {
        contents.removeAll()
        urlIndex.removeAll()
        visitedURLs.removeAll()
    }

    /// Removes content older than the specified date.
    ///
    /// - Parameter date: The cutoff date.
    public func removeContents(olderThan date: Date) {
        let toRemove = contents.values.filter { $0.crawledAt < date }
        for content in toRemove {
            remove(by: content.id)
        }
    }
}

// MARK: - Snapshot Support

extension MemoryStorage {
    /// Creates a snapshot of the current storage state.
    ///
    /// - Returns: A snapshot containing all content and visited URLs.
    public func createSnapshot() -> StorageSnapshot {
        StorageSnapshot(
            contents: Array(contents.values),
            visitedURLs: visitedURLs
        )
    }

    /// Restores the storage from a snapshot.
    ///
    /// This clears any existing data before restoring.
    ///
    /// - Parameter snapshot: The snapshot to restore from.
    public func restore(from snapshot: StorageSnapshot) {
        clear()
        for content in snapshot.contents {
            store(content)
        }
        for url in snapshot.visitedURLs {
            visitedURLs.insert(url)
        }
    }
}

// MARK: - StorageSnapshot

/// A snapshot of the storage state.
///
/// Can be used to save and restore the storage state.
public struct StorageSnapshot: Sendable {
    /// The stored content items.
    public let contents: [CrawledContent]

    /// The set of visited URLs.
    public let visitedURLs: Set<URL>

    /// The timestamp when the snapshot was created.
    public let createdAt: Date

    /// Creates a new storage snapshot.
    ///
    /// - Parameters:
    ///   - contents: The content items to include.
    ///   - visitedURLs: The visited URLs to include.
    public init(contents: [CrawledContent], visitedURLs: Set<URL>) {
        self.contents = contents
        self.visitedURLs = visitedURLs
        self.createdAt = Date()
    }
}
