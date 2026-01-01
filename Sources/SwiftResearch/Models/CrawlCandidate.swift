import Foundation

/// クロール候補（優先度スコア付きURL）
public struct CrawlCandidate: Sendable, Comparable {
    public let url: URL
    public let score: Double          // 0.0〜1.0（高いほど優先）
    public let title: String?
    public let reason: String?        // スコアの理由
    public let sourceURL: URL?        // このリンクを発見したページ
    public let addedAt: Date

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

    // 高いスコアが優先
    public static func < (lhs: CrawlCandidate, rhs: CrawlCandidate) -> Bool {
        lhs.score > rhs.score
    }
}

extension CrawlCandidate: Hashable {
    public static func == (lhs: CrawlCandidate, rhs: CrawlCandidate) -> Bool {
        lhs.url == rhs.url
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

/// クロール候補スタック（優先度順）
public actor CrawlCandidateStack {

    private var candidates: [CrawlCandidate] = []
    private var urlSet: Set<URL> = []

    public init() {}

    /// 候補を追加（優先度順にソート）
    public func push(_ candidate: CrawlCandidate) {
        guard !urlSet.contains(candidate.url) else { return }
        urlSet.insert(candidate.url)
        candidates.append(candidate)
        candidates.sort()  // 高スコア順
    }

    /// 複数の候補を追加
    public func push(_ newCandidates: [CrawlCandidate]) {
        for candidate in newCandidates {
            if !urlSet.contains(candidate.url) {
                urlSet.insert(candidate.url)
                candidates.append(candidate)
            }
        }
        candidates.sort()
    }

    /// 最高優先度の候補を取り出す
    public func pop() -> CrawlCandidate? {
        guard !candidates.isEmpty else { return nil }
        let candidate = candidates.removeFirst()
        urlSet.remove(candidate.url)
        return candidate
    }

    /// 上位N件を取り出す（並列処理用）
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

    /// 上位N件を確認（取り出さない）
    public func peek(count: Int) -> [CrawlCandidate] {
        Array(candidates.prefix(count))
    }

    /// URLが存在するか確認
    public func contains(_ url: URL) -> Bool {
        urlSet.contains(url)
    }

    public var count: Int { candidates.count }
    public var isEmpty: Bool { candidates.isEmpty }

    public func clear() {
        candidates.removeAll()
        urlSet.removeAll()
    }
}
