# SwiftResearch 仕様書

## 概要

SwiftResearchは、LLMが自律的にToolを呼び出して情報収集・分析を行うAgenticリサーチライブラリです。SwiftAgentフレームワーク上に構築され、ユーザーの質問に対してWeb検索・ページ取得・充足度評価を自律ループで実行し、根拠のある回答を生成します。

## 使用ライブラリ

| ライブラリ | 役割 |
|-----------|------|
| **SwiftAgent** | エージェントフレームワーク（Step, Tool, AgentSession, @Generable, @Contextable） |
| **RemarkKit** | HTML→Markdown変換、リンク抽出、Web検索結果パース |
| **OpenFoundationModels** | Apple FoundationModels バックエンド（デフォルト） |
| **OpenFoundationModelsOllama** | Ollama バックエンド（`USE_OTHER_MODELS=1`時） |
| **OpenFoundationModelsClaude** | Claude API バックエンド（`USE_OTHER_MODELS=1`時） |

## アーキテクチャ

### 全体構成

```
ResearchAgent
    │
    ▼
AgentSession(model, tools: [...])
    │
    ├── WebSearchTool           # Web検索（DuckDuckGo）
    ├── FetchToolWithLinks      # ページ取得 + リンク抽出（並列）
    └── EvaluateSufficiencyTool # 情報充足度評価（独自Session）
```

### LLM自律ループ

LLMがInstructionsに従い、適切なToolを自律的に呼び出すAgenticアーキテクチャです。明示的なフェーズ遷移やオーケストレーターは存在せず、LLMが状況に応じて次のアクションを判断します。

```
┌──────────────────────────────────────────────────┐
│  AgentSession                                     │
│                                                    │
│  1. Understand  ── LLMがクエリを分析              │
│       ↓                                            │
│  ┌────────────────────────────────────────────┐   │
│  │  2. Search   ── WebSearchTool 呼び出し     │   │
│  │       ↓                                    │   │
│  │  3. Fetch    ── FetchToolWithLinks 呼び出し │   │
│  │       ↓                                    │   │
│  │  4. Evaluate ── EvaluateSufficiencyTool    │   │
│  │       │         呼び出し                   │   │
│  │       ├─ 不十分 → Step 2 or 3 に戻る       │   │
│  │       └─ 十分   → ループ終了               │   │
│  └────────────────────────────────────────────┘   │
│       ↓                                            │
│  5. Answer ── 収集情報に基づき回答を生成          │
└──────────────────────────────────────────────────┘
```

### Toolパターン（構造化出力の信頼性）

AgentSession内で `respond(generating: T.self)` を使用すると、JSONスキーマが会話履歴に埋没し、LLMがスキーマを無視する問題が発生します。

EvaluateSufficiencyToolはこの問題を回避するため、**Tool内で独自のLanguageModelSessionを作成**します。独自SessionのInstructionsにJSONスキーマが含まれるため、構造化出力の成功率が向上します。

| パターン | スキーマ配置 | 成功率 |
|---------|-------------|--------|
| AgentSession内Generate | 会話履歴に埋没 | 低い |
| Tool内Session | Instructions内 | 高い |

## コンポーネント詳細

### ResearchAgent

リサーチの実行を担うメインクラス。AgentSessionを構成し、クエリを送信して結果を返す。

```swift
public final class ResearchAgent: Sendable {
    public init(
        model: some LanguageModel,
        configuration: Configuration = .default
    )

    public func research(_ query: String) async throws -> Result
}
```

#### ResearchAgent.Configuration

```swift
public struct Configuration: Sendable {
    public let maxURLs: Int           // デフォルト: 20
    public let blockedDomains: [String]  // デフォルト: []
    public let verbose: Bool          // デフォルト: false

    public static let `default` = Configuration()
}
```

#### ResearchAgent.Result

```swift
public struct Result: Sendable {
    public let objective: String      // 調査クエリ
    public let answer: String         // 生成された回答
    public let visitedURLs: [String]  // 訪問したURL一覧
    public let duration: Duration     // 実行時間
}
```

### WebSearchTool

DuckDuckGoを使用してWeb検索を実行し、結果URLリストを返すTool。

```swift
public struct WebSearchTool: Tool, Sendable {
    public typealias Arguments = WebSearchInput
    public typealias Output = WebSearchOutput

    public static let name = "WebSearch"

    public init(blockedDomains: [String] = [])
    public func call(arguments: WebSearchInput) async throws -> WebSearchOutput
}
```

#### WebSearchInput（@Generable）

```swift
@Generable
public struct WebSearchInput: Sendable {
    @Guide(description: "The search query keywords")
    public let query: String

    @Guide(description: "Maximum number of results to return (default: 10)")
    public let limit: Int
}
```

#### WebSearchOutput

```swift
public struct WebSearchOutput: Sendable {
    public let success: Bool
    public let results: [SearchResult]
    public let query: String
    public let message: String
}
```

#### SearchResult

```swift
public struct SearchResult: Sendable {
    public let title: String
    public let url: String
    public let snippet: String
}
```

### FetchToolWithLinks

複数URLを並列に取得し、Markdown変換とリンク抽出を行うTool。

```swift
public struct FetchToolWithLinks: Tool, Sendable {
    public typealias Arguments = FetchWithLinksInput
    public typealias Output = FetchWithLinksOutput

    public static let name = "WebFetch"

    public init()
    public func call(arguments: FetchWithLinksInput) async throws -> FetchWithLinksOutput
}
```

#### FetchWithLinksInput（@Generable）

```swift
@Generable
public struct FetchWithLinksInput: Sendable {
    @Guide(description: "List of URLs to fetch content from (parallel fetch)")
    public let urls: [String]
}
```

#### FetchWithLinksOutput

```swift
public struct FetchWithLinksOutput: Sendable {
    public let results: [SingleFetchResult]
    public var successCount: Int { get }
    public var failedCount: Int { get }
}
```

#### SingleFetchResult

```swift
public struct SingleFetchResult: Sendable {
    public let success: Bool
    public let content: String      // Markdown変換済みコンテンツ
    public let links: [PageLink]
    public let url: String
    public let message: String
}
```

#### PageLink

```swift
public struct PageLink: Sendable, Equatable {
    public let url: String
    public let text: String
}
```

### EvaluateSufficiencyTool

収集情報の充足度を評価するTool。独自のLanguageModelSessionを使用して構造化出力を生成する。

```swift
public struct EvaluateSufficiencyTool: Tool, Sendable {
    public typealias Arguments = EvaluateSufficiencyInput
    public typealias Output = EvaluateSufficiencyOutput

    public static let name = "EvaluateSufficiency"

    public init(model: some LanguageModel)
    public func call(arguments: EvaluateSufficiencyInput) async throws -> EvaluateSufficiencyOutput
}
```

#### EvaluateSufficiencyInput（@Generable）

```swift
@Generable
public struct EvaluateSufficiencyInput: Sendable {
    @Guide(description: "The user's research question or objective")
    public let objective: String

    @Guide(description: "Summary of information collected so far")
    public let collectedInfo: String

    @Guide(description: "Number of URLs visited")
    public let visitedCount: Int

    @Guide(description: "Maximum number of URLs allowed to visit")
    public let maxURLs: Int
}
```

#### EvaluateSufficiencyOutput

```swift
public struct EvaluateSufficiencyOutput: Sendable {
    public let isSufficient: Bool
    public let gaps: [String]
    public let recommendation: String
    public let reasoning: String
}
```

内部で `EvaluateSufficiencyResponse`（@Generable）を生成し、`EvaluateSufficiencyOutput` に変換する。

### SearchStep

キーワードから検索エンジン経由でURL一覧を取得するStep。評価フレームワーク等で直接使用する。

```swift
public struct SearchStep: Step, Sendable {
    public typealias Input = KeywordSearchInput
    public typealias Output = [URL]

    @Context private var contextConfig: SearchConfiguration

    public init(searchEngine: SearchEngine = .duckDuckGo, blockedDomains: [String] = [])
    public init()  // @Context使用

    public func run(_ input: KeywordSearchInput) async throws -> [URL]
}
```

#### KeywordSearchInput

```swift
public struct KeywordSearchInput: Sendable {
    public let keyword: String
}
```

**ドメインフィルタリング:**
- 検索エンジン内部リンクを除外（DuckDuckGo、Google全TLD、Bing、Yahoo、Yandex、Baidu）
- ユーザー指定のブロックリスト対応
- HTTPSのみ許可

## データモデル

### SearchConfiguration（@Contextable）

```swift
@Contextable
public struct SearchConfiguration: Sendable {
    public let searchEngine: SearchEngine        // デフォルト: .duckDuckGo
    public let requestDelay: Duration            // デフォルト: .milliseconds(500)
    public let allowedDomains: [String]?         // nilの場合は制限なし
    public let blockedDomains: [String]          // デフォルト: []
    public let researchConfiguration: ResearchConfiguration
    public let domainContext: String?             // クエリ曖昧性解消用

    public static let `default` = SearchConfiguration()
}
```

### SearchEngine

```swift
public enum SearchEngine: Sendable {
    case duckDuckGo
    case google
    case bing

    public func searchURL(for query: String) -> URL?
}
```

### ResearchConfiguration

```swift
public struct ResearchConfiguration: Sendable {
    public let maxURLs: Int  // デフォルト: 50（環境変数 MAX_URLS で上書き可能）

    public static let shared = ResearchConfiguration()
}
```

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

## LLM Instructions

`ResearchAgent.researchInstructions` がAgentSessionのInstructionsとして設定されます。手順は以下の5ステップで構成:

### Step 1: Understand the Query
クエリの主題・意図・範囲を分析し、検索キーワードを計画する。

### Step 2: Search
WebSearchToolを呼び出してキーワード検索を実行する。クエリと同じ言語でキーワードを使用する。

### Step 3: Fetch and Analyze Pages
FetchToolWithLinksを呼び出して複数URLを並列取得する。一度に3〜5件のURLを取得し、関連情報を抽出する。

### Step 4: Evaluate Sufficiency
EvaluateSufficiencyToolを呼び出して情報の充足度を評価する。不十分な場合はStep 2またはStep 3に戻る。

### Step 5: Generate Answer
取得コンテンツのみに基づいて回答を生成する。ソースURLを引用し、矛盾する情報があれば明記する。

**制約:**
- 最大URL数を超えない
- 同一URLを再訪問しない
- 権威あるソースを優先
- 最低1ページは取得してから回答する
- クエリと同じ言語で回答する

## ファイル構成

```
Sources/
├── SwiftResearch/
│   ├── ResearchAgent.swift               # メインリサーチエージェント
│   ├── SearchConfiguration.swift         # 検索エンジン設定（@Contextable）
│   ├── SearchError.swift                 # エラー定義
│   ├── ResearchConfiguration.swift       # グローバル設定（環境変数対応）
│   ├── SearchStep.swift                  # 検索実行Step
│   └── Tools/
│       ├── WebSearchTool.swift           # Web検索Tool
│       ├── FetchToolWithLinks.swift      # ページ取得 + リンク抽出Tool
│       └── EvaluateSufficiencyTool.swift # 充足度評価Tool（独自Session）
└── ResearchCLI/
    └── ResearchCLI.swift                 # CLIエントリポイント

Tests/
└── SwiftResearchTests/
    ├── AgentToolTests.swift              # ツールのユニットテスト
    ├── EvaluationModelTests.swift        # 評価モデルのユニットテスト
    ├── PromptTendencyTests.swift         # LLM応答傾向テスト
    ├── EvaluationBenchmarkTests.swift    # ベンチマークテスト
    └── Evaluation/                       # 評価フレームワーク
        ├── ModelContext.swift
        ├── ResearchResult+Evaluation.swift
        ├── StepModels.swift
        └── Models/
            ├── EvaluationConfiguration.swift
            └── EvaluationResult.swift

samples/
└── ResearchApp/                          # SwiftUIサンプルアプリ
```

## 設計原則

### セマンティック終了条件

従来のクローラーは固定制限で終了を制御しますが、SwiftResearchは**LLMによるセマンティック充足度判定**を採用しています。

- EvaluateSufficiencyToolが「目的に対して十分な情報が集まったか」を判断
- 不足情報を特定し、LLMが追加検索キーワードやURLを自動選択
- 無関係なページは早期スキップ

### セーフティリミット（maxURLs）

`maxURLs`はLLMの判断ミスや無限ループを防ぐための安全弁です。通常はセマンティック充足度判定が先に働いて終了します。

- `ResearchAgent.Configuration.maxURLs` — デフォルト: 20
- `ResearchConfiguration.maxURLs` — デフォルト: 50（環境変数 `MAX_URLS`）
- CLI `--limit` オプションで指定可能

### Toolパターンによる構造化出力の信頼性向上

構造化出力が必要な処理はTool内で独自Sessionを作成し、InstructionsにJSONスキーマを含めることで成功率を向上させます。EvaluateSufficiencyToolがこのパターンを実装しています。

### @Generable / @Guide によるスキーマ定義

Tool引数は `@Generable` マクロで定義し、各フィールドに `@Guide(description:)` でスキーマ情報を付与します。これによりLLMが正しい形式でTool呼び出し引数を生成できます。

## CLI

### 基本使用法

```bash
research "調査クエリ"
```

クエリを省略するとプロンプトで入力を求められる。

### オプション

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--limit <n>` | 50 | 訪問URL数の上限 |
| `--format <type>` | text | 出力形式（text / json） |
| `--verbose` | false | デバッグ情報・ツール呼び出し詳細を表示 |
| `--log <path>` | - | ログファイルパス |
| `--test-search` | false | 検索ステップのみテスト |
| `--test-fetch` | false | フェッチのみテスト |

**Ollamaモード（`USE_OTHER_MODELS=1`でビルド時）:**

| オプション | デフォルト | 説明 |
|-----------|-----------|------|
| `--claude` | false | Claude APIを使用 |
| `--model` | lfm2.5-thinking | Ollamaモデル名 |
| `--base-url` | http://127.0.0.1:11434 | OllamaサーバーURL |
| `--timeout` | 300.0 | リクエストタイムアウト（秒） |

### 使用例

```bash
# 基本的なリサーチ
research "SwiftUIの最新機能について"

# URL制限とJSON出力
research "Rust vs Go 比較" --limit 30 --format json

# デバッグ情報付き
research "量子コンピュータの現状" --verbose --log ./research.log

# 検索ステップのテスト
research "Swift Concurrency" --test-search

# URLフェッチのテスト
research "https://developer.apple.com/swift/" --test-fetch
```

## テスト

### テストスイート

| テストスイート | 目的 | 要件 |
|---------------|------|------|
| AgentToolTests | ツールのユニットテスト | なし |
| EvaluationModelTests | 評価データモデルの検証 | なし |
| PromptTendencyTests | LLM応答の傾向・分散分析 | Ollama |
| EvaluationBenchmarkTests | 品質・ファクトチェックのベンチマーク | Ollama |

### テスト実行

```bash
# ユニットテスト（Ollama不要）
swift test --filter EvaluationModelTests

# ベンチマークテスト（Ollama必要）
USE_OTHER_MODELS=1 swift test --filter EvaluationBenchmarkTests

# 全テスト
USE_OTHER_MODELS=1 swift test
```

## ビルド

```bash
# Apple FoundationModels（デフォルト）
swift build

# OpenFoundationModels（開発/テスト用）
USE_OTHER_MODELS=1 swift build
```
