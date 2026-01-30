# SwiftResearch 仕様書

## 概要

SwiftResearchは、SwiftAgentフレームワークを使用したAI駆動のリサーチツールです。Ollamaを使用してページコンテンツを分析し、**セマンティック充足度判定**によって情報収集の完了を判断します。5フェーズ構成で目的分析から最終レポート生成まで自動化します。

## 使用ライブラリ

| ライブラリ | 役割 |
|-----------|------|
| **SwiftAgent** | エージェントフレームワーク。Step-based設計の基盤 |
| **Selenops** | Webクローリングの基盤 |
| **RemarkKit** | 全てのWebアクセス。HTML→Markdown変換、リンク抽出 |
| **OpenFoundationModels-Ollama** | LLM分析（@Generableによる構造化出力） |

## アーキテクチャ

### 5フェーズ構成

```
┌─────────────────────────────────────────────────────────────────────┐
│                    SearchOrchestratorStep                           │
│                                                                      │
│  Phase 0: INPUT                                                     │
│       ↓                                                             │
│  Phase 1: OBJECTIVE ANALYSIS (目的分析)                             │
│       - キーワード生成                                               │
│       - ソクラテス的質問分解                                         │
│       - 成功基準設定                                                 │
│       ↓                                                             │
│  Phase 2-4 ループ                                                   │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  Phase 2: SEARCH (検索)                                        │ │
│  │       - キーワードで検索エンジン検索                             │ │
│  │       - URL一覧取得                                             │ │
│  │       ↓                                                        │ │
│  │  Phase 3: PARALLEL CONTENT REVIEW (並列コンテンツレビュー)       │ │
│  │       ┌─────────────────────────────────────┐                   │ │
│  │       │  CrawlContext (共有状態)            │                   │ │
│  │       │  - URLキュー                        │                   │ │
│  │       │  - 既知事実 (knownFacts)            │                   │ │
│  │       │  - 有用ドメイン学習                 │                   │ │
│  │       └─────────────────────────────────────┘                   │ │
│  │            ↓        ↓        ↓        ↓                        │ │
│  │       [Worker0] [Worker1] [Worker2] [Worker3]                   │ │
│  │       - 各ワーカー: fetch → LLMレビュー → DeepCrawl URL追加     │ │
│  │       - 既知事実を共有して重複抽出を防止                        │ │
│  │       ↓                                                        │ │
│  │  Phase 4: SUFFICIENCY CHECK (充足度チェック)                    │ │
│  │       - 十分 → ループ終了                                       │ │
│  │       - 不十分 → 追加キーワードで継続                           │ │
│  │       - 諦め → ループ終了                                       │ │
│  └────────────────────────────────────────────────────────────────┘ │
│       ↓                                                             │
│  Phase 5: RESPONSE BUILDING (応答構築)                              │
│       - 収集情報から最終レポート生成                                 │
│       ↓                                                             │
│  AggregatedResult                                                   │
└─────────────────────────────────────────────────────────────────────┘
```

### コンポーネント詳細

#### 1. SearchOrchestratorStep

5フェーズを統括するメインStep。

```swift
public struct SearchOrchestratorStep: Step, Sendable {
    typealias Input = SearchQuery
    typealias Output = AggregatedResult
}

public struct SearchQuery: Sendable {
    let objective: String        // 調査目的
    let maxVisitedURLs: Int      // 訪問URL数の上限（セーフティリミット、デフォルト: 100）
}
```

#### 2. SearchStep

検索エンジンを使用してキーワードからURLリストを取得するStep。

```swift
public struct SearchStep: Step, Sendable {
    typealias Input = KeywordSearchInput
    typealias Output = [URL]
}

public struct KeywordSearchInput: Sendable {
    let keyword: String
}
```

**ドメインフィルタリング:**
- 検索エンジン内部リンクを除外（Google全TLD、Bing、DuckDuckGo、Yahoo、Yandex、Baidu）
- ユーザー指定のブロックリスト対応
- HTTPSのみ許可

#### 3. CrawlCandidateStack

優先度付きクロール候補を管理するActor。

```swift
public actor CrawlCandidateStack {
    func push(_ candidate: CrawlCandidate)
    func push(_ candidates: [CrawlCandidate])
    func pop() -> CrawlCandidate?
    func pop(count: Int) -> [CrawlCandidate]
    func peek(count: Int) -> [CrawlCandidate]
    func contains(_ url: URL) -> Bool
    var count: Int { get async }
    var isEmpty: Bool { get async }
    func clear()
}
```

#### 4. CrawlContext

並列クロールの共有状態を管理するスレッドセーフなクラス。

```swift
public final class CrawlContext: @unchecked Sendable {
    // URL管理
    func enqueueURLs(_ urls: [URL])      // URLをキューに追加（重複除外）
    func dequeueURL() -> URL?            // 次のURLを取得
    func completeURL(_ url: URL)         // 処理完了を記録
    func isVisited(_ url: URL) -> Bool   // 訪問済みチェック

    // 結果管理
    func addResult(_ content: ReviewedContent)
    var reviewedContents: [ReviewedContent] { get }
    var relevantCount: Int { get }

    // 共有情報（レビュー精度向上用）
    func getKnownFacts(limit: Int) -> [String]  // 既知事実を取得
    func getRelevantDomains() -> Set<String>    // 有用ドメインを取得

    // 制御
    func markSufficient()                // 十分フラグを立てる
    var isSufficient: Bool { get }
    var hasMoreURLs: Bool { get }

    // 統計
    func getStatistics() -> (processed: Int, relevant: Int, queued: Int, inProgress: Int)
}
```

#### 5. MemoryStorage

インメモリでクロール結果を保存するActor。

```swift
public actor MemoryStorage {
    func store(_ content: CrawledContent)
    func store(_ newContents: [CrawledContent])
    func get(by id: UUID) -> CrawledContent?
    func get(by url: URL) -> CrawledContent?
    func getAll() -> [CrawledContent]
    func hasVisited(_ url: URL) -> Bool
    func markAsVisited(_ url: URL)
    var count: Int { get async }
    var visitedCount: Int { get async }
}
```

## データモデル

### CrawlCandidate

```swift
public struct CrawlCandidate: Sendable, Comparable {
    let url: URL
    let score: Double          // 0.0〜1.0（高いほど優先）
    let title: String?
    let reason: String?        // スコアの理由
    let sourceURL: URL?        // このリンクを発見したページ
    let addedAt: Date
}
```

### CrawledContent

```swift
public struct CrawledContent: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let title: String?
    let description: String?
    let markdown: String
    let links: [ExtractedLink]
    let crawledAt: Date
}

public struct ExtractedLink: Sendable, Hashable {
    let url: String
    let text: String?
}
```

### ReviewedContent

```swift
public struct ReviewedContent: Sendable {
    let url: URL
    let title: String?
    let extractedInfo: String  // 抽出した関連情報
    let isRelevant: Bool
}
```

### 統計情報

```swift
public struct AggregatedStatistics: Sendable {
    let totalPagesVisited: Int   // 訪問したページ総数
    let relevantPagesFound: Int  // 関連コンテンツ数
    let keywordsUsed: Int
    let duration: Duration
}
```

### 出力結果

```swift
public struct AggregatedResult: Sendable {
    let objective: String
    let questions: [String]                 // ソクラテス的質問
    let successCriteria: [String]           // 充足判定条件
    let reviewedContents: [ReviewedContent] // レビュー済みコンテンツ
    let responseMarkdown: String            // 最終応答
    let keywordsUsed: [String]
    let statistics: AggregatedStatistics
}
```

## LLMレスポンスモデル（@Generable）

### Phase 1: ObjectiveAnalysisResponse

```swift
@Generable
public struct ObjectiveAnalysisResponse: Sendable {
    let keywords: [String]        // 検索キーワード
    let questions: [String]       // ソクラテス的質問
    let successCriteria: [String] // 成功基準
}
```

### Phase 3: ContentReviewResponse

```swift
@Generable
public struct ContentReviewResponse: Sendable {
    let isRelevant: Bool
    let extractedInfo: String
    let shouldDeepCrawl: Bool
    let priorityLinks: [PriorityLink]
}

@Generable
public struct PriorityLink: Sendable {
    let index: Int      // リンクのインデックス（1始まり）
    let score: Double   // 関連度スコア
    let reason: String
}
```

### Phase 3.5: DeepCrawlReviewResponse

```swift
@Generable
public struct DeepCrawlReviewResponse: Sendable {
    let isRelevant: Bool
    let extractedInfo: String
    let shouldContinue: Bool  // 深掘り続行判断
    let reason: String
}
```

### Phase 4: SufficiencyCheckResponse

```swift
@Generable
public struct SufficiencyCheckResponse: Sendable {
    let isSufficient: Bool
    let shouldGiveUp: Bool
    let additionalKeywords: [String]
    let reasonMarkdown: String
}
```

### Phase 5: FinalResponseBuildingResponse

```swift
@Generable
public struct FinalResponseBuildingResponse: Sendable {
    let responseMarkdown: String
}
```

## 設定オプション

```swift
public struct SearchConfiguration: Sendable {
    let searchEngine: SearchEngine      // .duckDuckGo, .google, .bing
    let requestDelay: Duration          // デフォルト: .milliseconds(500)
    let modelName: String               // デフォルト: "gpt-oss:20b"
    let baseURL: URL                    // デフォルト: http://127.0.0.1:11434
    let timeout: TimeInterval           // デフォルト: 300.0
    let allowedDomains: [String]?       // nilの場合は制限なし
    let blockedDomains: [String]        // デフォルト: []
}
```

## CLI インターフェース

### 基本コマンド

```bash
# 目的ベースのリサーチ（推奨）
research-cli "Swift Concurrency best practices"

# オプション指定
research-cli "Swift Concurrency" \
  --limit 100 \
  --model gpt-oss:20b \
  --format json \
  --verbose

# ログファイル出力
research-cli "Swift 6の新機能" --log output.log
```

### テストコマンド

```bash
# 検索ステップのテスト
research-cli test-search "Swift Concurrency"

# フェッチのテスト
research-cli test-fetch https://example.com
```

### 出力例

```
═══════════════════════════════════════════
🎯 Phase 0: INPUT
═══════════════════════════════════════════
objective: Swift Concurrency best practices
maxVisitedURLs: 100

═══════════════════════════════════════════
📊 Phase 1: OBJECTIVE ANALYSIS
═══════════════════════════════════════════
keywords: [Swift Concurrency best practices, async await patterns, ...]
questions: [What are the key patterns?, ...]
successCriteria: [Primary documentation found, ...]
⏱️ Phase 1 duration: 2.3s

═══════════════════════════════════════════
🔍 Phase 2: SEARCH [Swift Concurrency best practices]
═══════════════════════════════════════════
Found 5 URLs:
  [1] https://example.com/swift-concurrency
  ...

═══════════════════════════════════════════
📄 Phase 3: PARALLEL CONTENT REVIEW
═══════════════════════════════════════════
   Queue: 10 URLs, Concurrency: 4
   [W0] → example.com
   [W1] → docs.swift.org
   [W2] → hackingwithswift.com
   [W3] → swiftbysundell.com
   [W0]    +2 deep URLs
   [W0] ✓ 12.3s Swift Concurrency provides structured...
   [W1] ✓ 15.7s Async/await allows non-blocking code...
   [W2]    +1 deep URLs
   [W2] ✓ 18.2s The actor model prevents data races...
   [W3] · 20.1s (not relevant)

Phase 3 Summary: processed=10, relevant=7
⏱️ Phase 3 total: 45.2s

═══════════════════════════════════════════
✓ Phase 4: SUFFICIENCY CHECK
═══════════════════════════════════════════
isSufficient: true
shouldGiveUp: false
→ SUFFICIENT, exiting loop

═══════════════════════════════════════════
📝 Phase 5: RESPONSE BUILDING
═══════════════════════════════════════════
input reviewedContents: 5 items
output responseMarkdown: 2500 chars

🏁 Complete!
   Visited: 8, Relevant: 5
   Keywords: 1
   Duration: 45.3s

═══════════════════════════════════════════
📊 Aggregated Crawl Results
═══════════════════════════════════════════

📌 Objective: Swift Concurrency best practices
🔑 Keywords: Swift Concurrency best practices
❓ Questions: What are the key patterns? / ...
✓ Criteria: Primary documentation found / ...

📈 Statistics:
   • Pages visited: 8
   • Relevant pages: 5
   • Keywords used: 1
   • Duration: 45s

📝 Response:
───────────────────────────────────────────
# Swift Concurrency Best Practices
...
```

## エラーハンドリング

### SearchError

```swift
public enum SearchError: Error, Sendable {
    case searchFailed(String)
    case fetchFailed(URL, String)
    case modelUnavailable
    case invalidConfiguration(String)
    case timeout
    case noURLsFound
    case invalidURL(String)
    case cancelled
}
```

## ファイル構成

```
Sources/
├── SwiftResearch/
│   ├── AgenticCrawler.swift              # エントリポイント
│   ├── Models/
│   │   ├── AnalysisResponse.swift        # @Generable LLMレスポンス
│   │   ├── CrawlCandidate.swift          # 優先度付き候補 + CrawlCandidateStack
│   │   ├── CrawlContext.swift            # 並列クロール共有状態（NEW）
│   │   ├── CrawledContent.swift          # クロール済みコンテンツ
│   │   ├── SearchError.swift            # エラー定義
│   │   ├── CrawlerInput.swift            # 設定・入力モデル
│   │   ├── CrawlerResult.swift           # 結果モデル（旧、参考用）
│   │   └── StepModels.swift              # Step入出力モデル
│   ├── Steps/
│   │   ├── SearchOrchestratorStep.swift  # 5フェーズオーケストレーター（並列対応）
│   │   └── SearchStep.swift              # 検索Step
│   └── Storage/
│       └── MemoryStorage.swift           # インメモリストレージ
└── ResearchCLI/
    └── ResearchCLI.swift                 # CLIエントリポイント

Tests/
└── SwiftResearchTests/
    └── MemoryStorageTests.swift
```

## 設計原則

### セマンティック終了条件

従来のクローラーは固定制限で終了を制御しますが、SwiftResearchは**LLMによるセマンティック充足度判定**を採用しています。

- 「目的に対して十分な情報が集まったか」をLLMが判断
- キーワードの数も、検索結果の数も、LLMが適切と判断する量を使用
- 不足情報を特定し、追加キーワードを自動生成
- 無関係なページは早期スキップ（リソース節約）

### セーフティリミット

`maxVisitedURLs`（CLI: `--limit`）は**セーフティリミット**として機能します。これはLLMの判断ミスや無限ループを防ぐための安全弁であり、通常の終了条件ではありません。

- デフォルト値: 100
- LLMが充足と判断する前にこの上限に達した場合、クロールを強制終了
- 通常はセマンティック充足度判定が先に働いて終了する

### AMD Framework参照

目的分析（Phase 1）では、AMD Framework (arXiv:2502.08557) に基づくソクラテス的質問分解を採用しています。

- **明確化**: 何を意味しているか？
- **前提検証**: 何を前提としているか？
- **含意探索**: 何が導かれるか？

### 並列処理アーキテクチャ

Phase 3では、複数のワーカーが並列でURLを処理します。

#### CrawlContext（共有状態）

- **スレッドセーフ**: NSLockによる排他制御
- **URLキュー**: 訪問済みURLの自動除外、動的なDeepCrawl URL追加
- **既知事実（knownFacts）**: 各ワーカーが抽出した情報を共有し、重複抽出を防止
- **有用ドメイン学習**: 2回以上関連ページが見つかったドメインを追跡

#### ワーカー動作

```
while (url = context.dequeueURL()) {
    if context.isSufficient { break }

    content = await fetch(url)
    knownFacts = context.getKnownFacts(limit: 5)

    review = await llm.review(content, knownFacts: knownFacts)
    context.addResult(review)

    if review.shouldDeepCrawl {
        context.enqueueURLs(review.priorityLinks)
    }

    context.completeURL(url)
}
```

#### パフォーマンス効果

- **並列処理**: 4ワーカー同時実行で処理時間を約50%削減
- **既知事実共有**: 重複情報の抽出を防ぎ、LLMコストを削減
- **動的キュー**: DeepCrawl URLを即座に他ワーカーが処理可能

### 深掘り（DeepCrawl）の制御

Phase 3では、関連性の高いページから発見されたリンクを深掘りします。LLMが履歴を考慮して続行判断を行い、無関係なページからのリンクは早期に打ち切ります。

## 今後の拡張予定

1. **永続化ストレージ** - SQLite/CoreData対応
2. **キャッシュ機能** - 取得済みページのキャッシュ
3. **レート制限** - ドメインごとのリクエスト制限
4. **認証対応** - Basic認証/OAuth対応サイトのクロール
5. **JavaScript対応** - SPAサイトのクロール（WebKit統合）
6. **ストリーミング** - リアルタイム結果表示
