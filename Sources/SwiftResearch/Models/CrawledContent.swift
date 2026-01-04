import Foundation

// MARK: - CrawledContent

/// Content retrieved from a crawled web page.
///
/// Represents the parsed content of a single web page, including
/// its metadata, markdown content, and extracted links.
///
/// ## Topics
///
/// ### Identification
/// - ``id``
/// - ``url``
///
/// ### Content
/// - ``title``
/// - ``description``
/// - ``markdown``
///
/// ### Links
/// - ``links``
///
/// ### Metadata
/// - ``crawledAt``
public struct CrawledContent: Identifiable, Sendable {
    /// The unique identifier for this content.
    public let id: UUID

    /// The URL of the crawled page.
    public let url: URL

    /// The page title, if available.
    public let title: String?

    /// The page description, if available.
    public let description: String?

    /// The page content in markdown format.
    public let markdown: String

    /// Links extracted from the page.
    public let links: [ExtractedLink]

    /// The timestamp when this page was crawled.
    public let crawledAt: Date

    /// Creates new crawled content.
    ///
    /// - Parameters:
    ///   - id: The unique identifier. Defaults to a new UUID.
    ///   - url: The URL of the crawled page.
    ///   - title: The page title, if available.
    ///   - description: The page description, if available.
    ///   - markdown: The page content in markdown format.
    ///   - links: Links extracted from the page.
    ///   - crawledAt: The timestamp when this page was crawled. Defaults to now.
    public init(
        id: UUID = UUID(),
        url: URL,
        title: String?,
        description: String?,
        markdown: String,
        links: [ExtractedLink],
        crawledAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.description = description
        self.markdown = markdown
        self.links = links
        self.crawledAt = crawledAt
    }
}

// MARK: - ExtractedLink

/// A link extracted from a web page.
///
/// Contains the URL and optional anchor text of the link.
public struct ExtractedLink: Sendable, Hashable {
    /// The URL of the link.
    public let url: String

    /// The anchor text of the link, if available.
    public let text: String?

    /// Creates a new extracted link.
    ///
    /// - Parameters:
    ///   - url: The URL of the link.
    ///   - text: The anchor text of the link, if available.
    public init(url: String, text: String?) {
        self.url = url
        self.text = text
    }
}

// MARK: - Hashable

extension CrawledContent: Hashable {
    public static func == (lhs: CrawledContent, rhs: CrawledContent) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
