import Foundation
import SwiftAgent
import RemarkKit

/// キーワード検索の入力
public struct KeywordSearchInput: Sendable {
    public let keyword: String

    public init(keyword: String) {
        self.keyword = keyword
    }
}

/// 検索エンジンを使用してキーワードからURLリストを取得するStep
public struct SearchStep: Step, Sendable {
    public typealias Input = KeywordSearchInput
    public typealias Output = [URL]

    private let searchEngine: SearchEngine
    private let blockedDomains: Set<String>

    public init(
        searchEngine: SearchEngine = .duckDuckGo,
        blockedDomains: [String] = []
    ) {
        self.searchEngine = searchEngine
        self.blockedDomains = Set(blockedDomains)
    }

    public func run(_ input: KeywordSearchInput) async throws -> [URL] {
        guard let searchURL = searchEngine.searchURL(for: input.keyword) else {
            throw CrawlerError.invalidURL(input.keyword)
        }

        printFlush("🔍 Searching: \(input.keyword)")

        // Remarkで検索結果ページを取得
        let remark = try await Remark.fetch(from: searchURL)

        // リンクを抽出
        let links = try remark.extractLinks()

        // URLをフィルタリングして返却
        var seenURLs: Set<URL> = []
        let urls = links
            .compactMap { URL(string: $0.url) }
            .filter { url in
                // 検索エンジン自体のURLは除外
                guard let host = url.host else { return false }

                // ブロックリストに含まれるドメインは除外
                if blockedDomains.contains(where: { host.contains($0) }) {
                    return false
                }

                // 検索エンジンの内部リンクは除外（パターンマッチで全TLD対応）
                let internalDomainPatterns = [
                    "duckduckgo.",   // duckduckgo.com, etc.
                    ".google.",      // www.google.com, www.google.co.jp, etc.
                    "google.com",    // google.com直接
                    ".bing.",        // www.bing.com, etc.
                    "bing.com",      // bing.com直接
                    "yahoo.com",     // yahoo.com
                    ".yahoo.",       // search.yahoo.co.jp, etc.
                    "yandex.",       // yandex.ru, yandex.com, etc.
                    "baidu.com",     // baidu.com
                ]
                if internalDomainPatterns.contains(where: { host.contains($0) }) {
                    return false
                }

                // HTTPSのみ許可
                return url.scheme == "https"
            }
            .filter { url in
                // 重複除去（順序を保持）
                if seenURLs.contains(url) {
                    return false
                }
                seenURLs.insert(url)
                return true
            }

        printFlush("   Found \(urls.count) URLs")

        if urls.isEmpty {
            throw CrawlerError.noURLsFound
        }

        return Array(urls)
    }
}

// MARK: - Convenience Extensions

extension SearchStep {
    /// 設定から SearchStep を作成
    public static func from(configuration: CrawlerConfiguration) -> SearchStep {
        SearchStep(
            searchEngine: configuration.searchEngine,
            blockedDomains: configuration.blockedDomains
        )
    }
}
