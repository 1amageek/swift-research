import Foundation

/// インメモリでクロール結果を保存するストレージ
public actor MemoryStorage {

    // MARK: - Properties

    private var contents: [UUID: CrawledContent] = [:]
    private var urlIndex: [URL: UUID] = [:]
    private var visitedURLs: Set<URL> = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Storage Operations

    /// コンテンツを保存する
    public func store(_ content: CrawledContent) {
        contents[content.id] = content
        urlIndex[content.url] = content.id
        visitedURLs.insert(content.url)
    }

    /// 複数のコンテンツを一括保存する
    public func store(_ newContents: [CrawledContent]) {
        for content in newContents {
            store(content)
        }
    }

    /// IDでコンテンツを取得する
    public func get(by id: UUID) -> CrawledContent? {
        contents[id]
    }

    /// URLでコンテンツを取得する
    public func get(by url: URL) -> CrawledContent? {
        guard let id = urlIndex[url] else { return nil }
        return contents[id]
    }

    /// 全てのコンテンツを取得する
    public func getAll() -> [CrawledContent] {
        Array(contents.values).sorted { $0.crawledAt < $1.crawledAt }
    }

    // MARK: - URL Tracking

    /// URLが訪問済みかどうかを確認する
    public func hasVisited(_ url: URL) -> Bool {
        visitedURLs.contains(url)
    }

    /// URLを訪問済みとしてマークする
    public func markAsVisited(_ url: URL) {
        visitedURLs.insert(url)
    }

    /// 訪問済みURLの一覧を取得する
    public func getVisitedURLs() -> Set<URL> {
        visitedURLs
    }

    // MARK: - Statistics

    /// 保存されているコンテンツの数を取得する
    public var count: Int {
        contents.count
    }

    /// 訪問済みURLの数を取得する
    public var visitedCount: Int {
        visitedURLs.count
    }

    /// 全リンク数を取得する
    public var totalLinksCount: Int {
        contents.values.reduce(0) { $0 + $1.links.count }
    }

    // MARK: - Search

    /// タイトルでコンテンツを検索する
    public func search(titleContaining query: String) -> [CrawledContent] {
        let lowercasedQuery = query.lowercased()
        return contents.values.filter {
            $0.title?.lowercased().contains(lowercasedQuery) ?? false
        }
    }

    /// Markdownコンテンツで検索する
    public func search(contentContaining query: String) -> [CrawledContent] {
        let lowercasedQuery = query.lowercased()
        return contents.values.filter {
            $0.markdown.lowercased().contains(lowercasedQuery)
        }
    }

    /// ドメインでコンテンツをフィルタリングする
    public func getContents(forDomain domain: String) -> [CrawledContent] {
        contents.values.filter {
            $0.url.host == domain
        }
    }

    // MARK: - Aggregation

    /// Markdownコンテンツを結合して取得する
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

    /// 要約用のコンテンツを取得する（トークン制限考慮）
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

    /// 特定のコンテンツを削除する
    public func remove(by id: UUID) {
        if let content = contents.removeValue(forKey: id) {
            urlIndex.removeValue(forKey: content.url)
        }
    }

    /// URLでコンテンツを削除する
    public func remove(by url: URL) {
        if let id = urlIndex.removeValue(forKey: url) {
            contents.removeValue(forKey: id)
        }
        visitedURLs.remove(url)
    }

    /// 全てのデータをクリアする
    public func clear() {
        contents.removeAll()
        urlIndex.removeAll()
        visitedURLs.removeAll()
    }

    /// 古いコンテンツを削除する（指定日時より前）
    public func removeContents(olderThan date: Date) {
        let toRemove = contents.values.filter { $0.crawledAt < date }
        for content in toRemove {
            remove(by: content.id)
        }
    }
}

// MARK: - Snapshot Support

extension MemoryStorage {
    /// ストレージのスナップショットを作成する
    public func createSnapshot() -> StorageSnapshot {
        StorageSnapshot(
            contents: Array(contents.values),
            visitedURLs: visitedURLs
        )
    }

    /// スナップショットから復元する
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

/// ストレージのスナップショット
public struct StorageSnapshot: Sendable {
    public let contents: [CrawledContent]
    public let visitedURLs: Set<URL>
    public let createdAt: Date

    public init(contents: [CrawledContent], visitedURLs: Set<URL>) {
        self.contents = contents
        self.visitedURLs = visitedURLs
        self.createdAt = Date()
    }
}
