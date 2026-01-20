# SwiftResearch プロンプトフロー設計書

## 概要

SwiftResearchの各Phaseで使用されるLLMプロンプトと、それぞれが受け取る入力情報を整理したドキュメント。

---

## 現在のフロー

```
SearchQuery(objective, maxVisitedURLs)
         │
         ▼
    Phase 0: Initial Search
         │
         ▼
    Phase 1: Objective Analysis
         │
         ▼
    Phase 2-4: Search Loop
    ├── Phase 2: Search
    ├── Phase 3: Content Review
    └── Phase 4: Sufficiency Check
         │
         ▼
    Phase 5: Response Building
         │
         ▼
    AggregatedResult
```

---

## Phase別プロンプト詳細

### Phase 0: Initial Search

**ファイル**: `SearchOrchestratorStep.swift` (lines 576-581)

**メソッド**: `extractBasicInfo()`

**目的**: 上位2件のURLから背景情報を抽出

**入力**:
| 変数 | 型 | 説明 |
|------|-----|------|
| query | String | 検索クエリ |
| markdown | String | ページ内容 (3000字まで) |

**出力**: backgroundInfo (100-200字の要約)

**プロンプト例**:
```
以下のページから「What is Swift?」に関する基本情報を抽出してください。
100-200字程度で簡潔に要約してください。
```

---

### Phase 1: Objective Analysis

**ファイル**: `ObjectiveAnalysisStep.swift` (lines 70-98)

**目的**: 検索キーワード、質問、成功基準を生成

**入力**:
| 変数 | 型 | 説明 |
|------|-----|------|
| objective | String | 研究目的 |
| backgroundInfo | String? | Phase 0で取得した背景情報 |

**出力**: `ObjectiveAnalysisResponse`
- keywords: [String] - 検索キーワード
- questions: [String] - ソクラテス的質問
- successCriteria: [String] - 成功基準

**プロンプト構造**:
```
あなたはリサーチアシスタントです。
以下の研究目的を分析し、効果的な検索戦略を立ててください。

## 研究目的
{objective}

## 背景情報
{backgroundInfo}

### 1. 検索キーワード（keywords）
...
### 2. ソクラテス的質問（questions）
...
### 3. 成功基準（successCriteria）
...
```

---

### Phase 3: Content Review

**ファイル**: `ContentReviewStep.swift` (lines 107-126)

**目的**: ページ内容の関連性判定と情報抽出

**入力**:
| 変数 | 型 | 説明 |
|------|-----|------|
| objective | String | 研究目的 |
| title | String | ページタイトル |
| content | String | ページ内容 (行番号付き) |
| linksInfo | String | 上位5件のリンク |
| knownFacts | [String] | 既に収集した情報 |
| relevantDomains | Set<String> | 関連ドメイン |

**出力**: `ContentReviewResponse`
- isRelevant: Bool - 関連性
- extractedInfo: String - 抽出情報
- shouldDeepCrawl: Bool - 深掘りするか
- priorityLinks: [Int] - 優先リンクのインデックス
- relevantRanges: [[Int]] - 関連行範囲

**プロンプト構造**:
```
## 研究目的
{objective}

## 既に収集した情報（重複を避けること）
{knownFacts}

## ページタイトル
{title}

## ページ内容
{content}

## リンク一覧
{linksInfo}
```

---

### Phase 4: Sufficiency Check

**ファイル**: `SufficiencyCheckStep.swift` (lines 100-145)

**目的**: 情報の十分性評価と継続判定

**入力**:
| 変数 | 型 | 説明 |
|------|-----|------|
| objective | String | 研究目的 |
| successCriteria | [String] | 成功基準 |
| collectedInfo | String | 収集情報のサマリー (最大10件) |
| searchRoundNumber | Int | 現在のラウンド番号 |
| newRelevantThisRound | Int | このラウンドの新規関連ページ数 |
| relevantCount | Int | 関連ページ総数 |

**出力**: `SufficiencyCheckResponse`
- isSufficient: Bool - 十分か
- shouldGiveUp: Bool - 諦めるか
- additionalKeywords: [String] - 追加キーワード
- reasonMarkdown: String - 理由
- successCriteria: [String] - 更新された成功基準

**プロンプト構造**:
```
## 研究目的
{objective}

## 成功基準
{successCriteria}

## 収集済み情報
{collectedInfo}

## 統計
- ラウンド: {searchRoundNumber}
- このラウンドの新規関連ページ: {newRelevantThisRound}
- 関連ページ総数: {relevantCount}

### 1. isSufficient（十分か？）
...
### 2. additionalKeywords（追加キーワード）
...
### 3. shouldGiveUp（諦めるか？）
...
```

---

### Phase 5: Response Building

**ファイル**: `ResponseBuildingStep.swift` (lines 111-132)

**目的**: 最終回答のMarkdown生成

**入力**:
| 変数 | 型 | 説明 |
|------|-----|------|
| objective | String | 研究目的 |
| questions | [String] | ソクラテス的質問 |
| successCriteria | [String] | 成功基準 |
| contextSection | String | 関連ページからの抜粋 |

**出力**: `FinalResponseBuildingResponse`
- responseMarkdown: String - 最終回答

**プロンプト構造**:
```
## 研究目的
{objective}

## 回答すべき質問
{questions}

## 成功基準
{successCriteria}

## 収集情報
{contextSection}

上記の情報を基に、研究目的に対する包括的な回答を生成してください。
```

---

## 課題: ドメインコンテキストの欠落

### 問題

曖昧なクエリ（例: "What is Swift?"）が誤解釈される：

```
"What is Swift?"
    ↓ (ドメインコンテキストなし)
Phase 0: 上位2件がSWIFT(金融)のページ
    ↓
backgroundInfo: 「SWIFTは1973年に設立された金融ネットワーク...」
    ↓
Phase 1: 金融系キーワードを生成
    ↓
Phase 3: プログラミング関連ページを「非関連」と判定
    ↓
Phase 4: 「関連ページなし」→ GIVE UP
    ↓
Coverage: 1/10
```

### 原因

`SearchQuery` にドメイン情報がない：

```swift
// 現在
public struct SearchQuery {
    public let objective: String
    public let maxVisitedURLs: Int
    // ⚠️ domainContext がない
}
```

`EvaluationTask.Persona.domain` の情報が伝播していない。

---

## 実装済み: domainContext の追加

### 1. CrawlerConfiguration の拡張 (@Contextable)

```swift
@Contextable
public struct CrawlerConfiguration: Sendable {
    // 既存フィールド...

    /// Domain context for query disambiguation.
    public let domainContext: String?
}
```

### 2. 各Stepでの利用 (@Context)

```swift
public struct ObjectiveAnalysisStep: Step, Sendable {
    @Session var session: LanguageModelSession
    @Context var config: CrawlerConfiguration  // 暗黙的に伝播

    func run(_ input: Input) async throws -> Output {
        let domainSection = config.domainContext.map { context in
            """
            ## Domain Context
            \(context)
            Interpret the query from this domain's perspective.
            """
        } ?? ""
        // ...
    }
}
```

### 3. 各Phaseへの伝播

| Phase | Step | プロンプトへの追加 |
|-------|------|------------------|
| 0 | extractBasicInfo | "Interpret the query from this domain's perspective." |
| 1 | ObjectiveAnalysisStep | "Interpret the query from this domain's perspective and generate relevant keywords." |
| 3 | ContentReviewStep | "Evaluate relevance from this domain's perspective." |
| 4 | SufficiencyCheckStep | "Evaluate sufficiency from this domain's perspective." |
| 5 | ResponseBuildingStep | "Generate the response from this domain's perspective." |

### 4. 使用例

```swift
// Personaからドメインコンテキストを取得
let persona = Persona(domain: .technology, ...)

// CrawlerConfigurationに設定
let crawlerConfig = CrawlerConfiguration(
    researchConfiguration: researchConfig,
    domainContext: persona.domain.domainDescription
    // → "Software development, AI, hardware, cybersecurity"
)

// SearchOrchestratorStepに渡す
let orchestrator = SearchOrchestratorStep(
    session: session,
    configuration: crawlerConfig
)

// 全Stepで自動的にdomainContextが利用可能
```

### 5. 改善後のフロー

```
CrawlerConfiguration
└─ domainContext: "Software development, AI, ..." ← Persona.domain から
         │
         ▼ (@Context で暗黙的に伝播)

Phase 0: "Interpret the query from this domain's perspective."
         │
Phase 1: "Interpret the query from this domain's perspective and generate relevant keywords."
         │
Phase 3: "Evaluate relevance from this domain's perspective."
         │
Phase 4: "Evaluate sufficiency from this domain's perspective."
         │
Phase 5: "Generate the response from this domain's perspective."
         │
         ▼
正しい解釈: "Swift" = Swift プログラミング言語
```

---

## 期待効果

| 指標 | 改善前 | 改善後（期待） |
|------|--------|---------------|
| クエリ曖昧性解消 | なし | ドメインで解決 |
| Coverage | 1/10 | 7+/10 |
| 早期GIVE UP | 頻発 | 減少 |
| 関連ページ判定精度 | 33% | 80%+ |

---

## 実装優先度

1. **SearchQuery.domainContext 追加** - 基盤
2. **Phase 0-1 プロンプト修正** - 最も効果が高い
3. **Phase 3 プロンプト修正** - 関連性判定改善
4. **Phase 4-5 プロンプト修正** - 仕上げ

---

## 関連ファイル

- `Sources/SwiftResearch/Models/StepModels.swift` - SearchQuery
- `Sources/SwiftResearch/Steps/SearchOrchestratorStep.swift` - Phase 0
- `Sources/SwiftResearch/Steps/ObjectiveAnalysisStep.swift` - Phase 1
- `Sources/SwiftResearch/Steps/ContentReviewStep.swift` - Phase 3
- `Sources/SwiftResearch/Steps/SufficiencyCheckStep.swift` - Phase 4
- `Sources/SwiftResearch/Steps/ResponseBuildingStep.swift` - Phase 5
