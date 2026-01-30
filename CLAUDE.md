# SwiftResearch

LLMを活用した自律的Webリサーチライブラリ。ユーザーの質問に対して、Web検索・情報収集・分析を自動で行い、根拠のある回答を生成する。

## プロジェクト構成

```
SwiftResearch/
├── Sources/SwiftResearch/
│   ├── Agent/                            # Agenticアーキテクチャ
│   │   ├── ResearchAgent.swift           # メインリサーチエージェント
│   │   ├── ResearchResult+Evaluation.swift # 評価ブリッジ
│   │   └── Tools/                        # AgentSession用ツール
│   │       ├── WebSearchTool.swift
│   │       ├── FetchToolWithLinks.swift
│   │       └── EvaluateSufficiencyTool.swift
│   ├── Steps/                            # 処理ステップ
│   │   └── SearchStep.swift              # 検索実行Step（評価用）
│   ├── Models/                           # データモデル
│   │   ├── StepModels.swift              # ReviewedContent, AggregatedResult等
│   │   ├── CrawlerConfiguration.swift    # 検索エンジン設定
│   │   ├── ResearchConfiguration.swift   # リサーチ設定
│   │   ├── CrawlerError.swift            # エラー定義
│   │   └── ModelContext.swift            # モデルコンテキスト
│   └── Evaluation/                       # 評価フレームワーク
│       ├── QualityEvaluation/            # 品質評価
│       ├── FactChecking/                 # ファクトチェック
│       └── TaskConstruction/             # タスク構築
├── Sources/ResearchCLI/                  # CLIツール
├── Tests/SwiftResearchTests/             # テストスイート
└── samples/ResearchApp/                  # SwiftUI サンプルアプリ
```

## アーキテクチャ

### ResearchAgent

LLMが自律的にToolを呼び出してリサーチを実行するAgenticアーキテクチャ。

```swift
let agent = ResearchAgent(
    model: model,
    configuration: .init(maxURLs: 20)
)

let result = try await agent.research("Swift Concurrencyとは？")
print(result.answer)
```

**構成要素:**

```
ResearchAgent
    │
    ▼
AgentSession(model, tools: [...])
    │
    ├── WebSearchTool       # Web検索
    ├── FetchToolWithLinks  # ページ取得
    └── EvaluateSufficiencyTool  # 情報十分性評価
```

LLMがInstructionsに従い、適切なToolを自律的に呼び出す。

### コア設計

| コンポーネント | 責務 |
|---------------|------|
| `ResearchAgent` | AgentSessionを使用した自律リサーチ |
| `AgentSession` | LLMとToolの対話を管理 |
| `WebSearchTool` | Web検索を実行 |
| `FetchToolWithLinks` | ページ取得とリンク抽出 |
| `EvaluateSufficiencyTool` | 情報十分性を評価（内部で独自Session使用） |

### ResearchAgent.Result

```swift
public struct Result: Sendable {
    public let objective: String
    public let answer: String
    public let visitedURLs: [String]
    public let duration: Duration
}
```

評価フレームワークとの互換性のため、`toAggregatedResult()` メソッドで `AggregatedResult` に変換可能。

## SwiftAgent 基本概念

### Step プロトコル

```swift
public protocol Step<Input, Output> {
    func run(_ input: Input) async throws -> Output
}
```

`Input` → `Output` の非同期変換単位。本プロジェクトの全Stepはこれを実装。

### Agent プロトコル

```swift
public protocol Agent: Step where Input == Body.Input, Output == Body.Output {
    associatedtype Body: Step
    @StepBuilder var body: Self.Body { get }
}
```

`body`を定義するだけで`run`が自動実装される宣言的なStep合成。

**使い分け:**
- `Step`: 複雑なロジック、条件分岐、共有状態が必要な場合
- `Agent`: シンプルなパイプライン、宣言的な合成

```swift
// Agent例
struct Translator: Agent {
    @Session var session: LanguageModelSession
    var body: some Step<String, String> {
        GenerateText(session: session) { Prompt("Translate: \($0)") }
    }
}
```

### @Generable（構造化出力）

LLMの応答を型安全に取得:

```swift
@Generable
public struct ObjectiveAnalysisResponse: Sendable {
    @Guide(description: "検索キーワード")
    public let keywords: [String]

    @Guide(description: "成功基準")
    public let successCriteria: [String]
}

// 使用
let response = try await session.respond(generating: ObjectiveAnalysisResponse.self) {
    Prompt(prompt)
}
```

**Enum対応:** String型enumに`@Generable`を適用可能:

```swift
@Generable
public enum Difficulty: String {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"
}

@Generable
public struct TaskResponse: Sendable {
    @Guide(description: "タスクの難易度")
    public let difficulty: Difficulty  // Enum型を直接使用
}
```

**制限:** Dictionary型は未サポート

### Tool と構造化出力

AgentSessionでの会話中に`respond(generating: T.self)`を使用すると、JSONスキーマがInstructionsに含まれない場合がある。これがLLMのスキーマ無視によるJSON出力エラーの原因となる。

**解決策: Toolパターン**

Toolは呼び出し時に独自のSessionを作成し、InstructionsにJSONスキーマを含めることで成功率を向上させる。

```swift
// EvaluateSufficiencyTool: 別Sessionで構造化出力を実行
public struct EvaluateSufficiencyTool: Tool {
    public typealias Arguments = SufficiencyInput
    public typealias Output = SufficiencyOutput

    private let model: any LanguageModel

    public func call(arguments: Arguments) async throws -> Output {
        // Tool内で新しいSessionを作成
        // このSessionのInstructionsにはJSONスキーマが含まれる
        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: sufficiencyInstructions
        )

        let response = try await session.respond(
            to: buildPrompt(arguments),
            generating: SufficiencyOutput.self
        )
        return response.content
    }
}
```

**パターン比較:**

| パターン | スキーマ配置 | 成功率 |
|---------|-------------|--------|
| AgentSession内Generate | 会話履歴に埋没 | 低い |
| Tool内Session | Instructions内 | 高い |

**評価ToolをResearchAgentに統合する場合:**

```swift
// ResearchAgentにファクトチェック機能を追加
let session = AgentSession(
    model: model,
    tools: [
        searchTool,
        fetchTool,
        sufficiencyTool,
        // 評価Tools（各Tool内で独自Sessionを使用）
        StatementExtractorTool(model: model),
        FactVerifierTool(model: model)
    ]
) {
    Instructions(...)
}
```

## Security（参考）

SwiftAgentのセキュリティ機能。本プロジェクトでは未使用だが、ツール実行制限が必要な場合に活用可能。

### Permission

ツール実行の許可/拒否をルールで制御:

```swift
PermissionConfiguration(
    allow: [.tool("Read"), .bash("git:*")],
    deny: [.bash("rm:*")],
    finalDeny: [.bash("sudo:*")],  // Override不可
    defaultAction: .ask
)
```

### Sandbox

Bashコマンドのファイル/ネットワークアクセスを制限（macOS専用）:

```swift
SandboxExecutor.Configuration(
    networkPolicy: .local,
    filePolicy: .workingDirectoryOnly
)
```

### Guardrail

Step単位で宣言的にセキュリティを適用:

```swift
FetchData()
    .guardrail {
        Allow(.tool("Read"))
        Deny(.bash("rm:*"))
        Sandbox(.restrictive)
    }
```

## ビルド

```bash
# Apple FoundationModels（デフォルト）
swift build

# OpenFoundationModels（開発/テスト用）
USE_OTHER_MODELS=1 swift build
```

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
| `--verbose` | false | 各フェーズのLLM出力を表示 |
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

# ログ出力付き
research "量子コンピュータの現状" --verbose --log ./research.log

# 検索ステップのテスト
research "Swift Concurrency" --test-search

# URLフェッチのテスト
research "https://developer.apple.com/swift/" --test-fetch
```

## テスト

### テストアーキテクチャ

```
Tests/SwiftResearchTests/
├── EvaluationModelTests.swift      # 評価モデルのユニットテスト
├── PromptTendencyTests.swift       # LLM応答傾向テスト
└── EvaluationBenchmarkTests.swift  # ベンチマークテスト
```

| テストスイート | 目的 | 要件 |
|---------------|------|------|
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

### 評価フレームワーク

リサーチ品質を多次元で評価:

```
Research実行
    │
    ├── Quality評価 (AdaptiveQualityStep)
    │   ├── Coverage      # 網羅性
    │   ├── Insight       # 洞察力
    │   ├── Instruction Following
    │   ├── Clarity       # 明確さ
    │   ├── Technical Accuracy
    │   └── Source Diversity
    │
    └── FactCheck (FactCheckOrchestratorStep)
        ├── 声明抽出
        ├── 証拠収集
        └── 検証判定 (correct/incorrect/unknown)
```

### ベンチマーク結果 (2026-01-24)

**テストクエリ:** "What is the current population of Tokyo?"
**モデル:** lfm2.5-thinking (Ollama)

| メトリクス | スコア | ベースライン |
|-----------|--------|-------------|
| Overall | 92.8/100 | ≥70 |
| Quality | 88.0/100 | ≥60 |
| Factual Accuracy | 100% | - |

**Quality次元別:**

| 次元 | スコア |
|------|--------|
| Coverage | 5/10 |
| Insight | 7/10 |
| Instruction Following | 10/10 |
| Clarity | 10/10 |
| Technical Accuracy | 10/10 |
| Source Diversity | 10/10 |

**改善点:**
- Coverage: 地域差の分析が浅い
- Insight: 成長要因の議論が不足
