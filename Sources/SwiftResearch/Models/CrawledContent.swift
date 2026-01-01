import Foundation

/// クロールで取得したコンテンツを表す構造体
public struct CrawledContent: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let title: String?
    public let description: String?
    public let markdown: String
    public let links: [ExtractedLink]
    public let crawledAt: Date

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

/// 抽出されたリンク情報
public struct ExtractedLink: Sendable, Hashable {
    public let url: String
    public let text: String?

    public init(url: String, text: String?) {
        self.url = url
        self.text = text
    }
}

extension CrawledContent: Hashable {
    public static func == (lhs: CrawledContent, rhs: CrawledContent) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
