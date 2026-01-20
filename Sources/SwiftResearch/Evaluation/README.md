# DeepResearchEval

SwiftResearchの出力品質を評価するフレームワーク。

## 概要

```
研究出力 → 品質評価 → ファクトチェック → 総合スコア
```

## コンポーネント

### 品質評価 (QualityEvaluation)

| Step | 責務 |
|------|------|
| DimensionGeneratorStep | タスク固有の評価次元を動的生成 |
| DimensionScorerStep | 各次元を1-10でスコアリング |
| AdaptiveQualityStep | 品質評価のオーケストレーション |

**評価次元**:
- 一般次元 (4つ): Coverage, Insight, Instruction Following, Clarity
- タスク固有次元 (最大3つ): LLMがタスクに応じて動的生成

### ファクトチェック (FactChecking)

| Step | 責務 |
|------|------|
| StatementExtractorStep | 検証可能な事実文を抽出 |
| EvidenceRetrievalStep | Web検索で証拠を収集 |
| FactVerifierStep | Right/Wrong/Unknown を判定 |
| FactCheckOrchestratorStep | ファクトチェックのオーケストレーション |

## ベンチマーク結果

### Benchmark #2: QueryDisambiguationStep導入後

**実行日**: 2025-01-20

**テスト条件**:
- クエリ: "What is Swift?"
- URL制限: 5
- LLM: Apple SystemLanguageModel
- Domain Context: "Software development, AI, hardware, cybersecurity"

**改善点**: QueryDisambiguationStepによりクエリを事前に書き換え
```
"What is Swift?" → "Swift programming language Apple"
```

**研究フェーズ**:
| 指標 | Benchmark #1 | Benchmark #2 | 変化 |
|------|--------------|--------------|------|
| 実行時間 | 116.7s | 278.5s | +161.8s |
| 訪問URL数 | 3 | 5 | +2 |
| 関連ページ数 | 0 | **3** | **+3** ✅ |
| 出力文字数 | 945 | 1897 | +952 |

**評価結果**:
| 指標 | Benchmark #1 | Benchmark #2 | 変化 |
|------|--------------|--------------|------|
| Quality Score | 44.7/100 | 31.0/100 | -13.7 |
| Fact Check | 0% | N/A (timeout) | - |

**次元別スコア**:
| 次元 | Benchmark #2 | 種別 | 備考 |
|------|--------------|------|------|
| Coverage | 5/10 | 一般 | fallback (parse error) |
| Insight | 5/10 | 一般 | fallback (parse error) |
| Instruction Following | 3/10 | 一般 | |
| Clarity | 5/10 | 一般 | |
| Version Relevance | 1/10 | タスク固有 | |
| Ecosystem Coverage | 1/10 | タスク固有 | |
| Developer Adoption Insight | 1/10 | タスク固有 | |

**Background Info比較**:
| Benchmark | 内容 |
|-----------|------|
| #1 | SWIFT金融ネットワーク（誤解釈） |
| #2 | "Swift is Apple's modern, safe, high-performance language..." ✅ |

**検索結果（Benchmark #2）**:
```
[1] https://developer.apple.com/swift/
[2] https://www.swift.org/
[3] https://en.wikipedia.org/wiki/Swift_(programming_language)
[4] https://www.apple.com/lae/swift/
[5] https://docs.swift.org/swift-book/...
```

**分析**:
- ✅ QueryDisambiguationが正常に動作（クエリ書き換え成功）
- ✅ 関連ページ検出が0→3に改善
- ✅ Background infoが正しいドメイン（プログラミング言語）
- ⚠️ Quality Scoreは低下（dictionaryExpectedエラーによるfallback）
- ⚠️ Fact Checkがタイムアウト（証拠検索でスタック）

---

### Benchmark #1: 初期実装（ドメインコンテキストなし）

**実行日**: 2025-01-20

**テスト条件**:
- クエリ: "What is Swift?"
- URL制限: 3
- LLM: Apple SystemLanguageModel

**研究フェーズ**:
| 指標 | 値 |
|------|-----|
| 実行時間 | 116.7s |
| 訪問URL数 | 3 |
| 関連ページ数 | 1 |
| 出力文字数 | 945 chars |

**評価結果**:
| 指標 | スコア |
|------|--------|
| Overall | 26.8/100 |
| Quality | 44.7/100 |
| Factual Accuracy | 0.0% |

**次元別スコア**:
| 次元 | スコア | 種別 |
|------|--------|------|
| Coverage | 1/10 | 一般 |
| Insight | 1/10 | 一般 |
| Instruction Following | 3/10 | 一般 |
| Clarity | 7/10 | 一般 |
| Technical Accuracy | 5/10 | タスク固有 |
| Source Credibility | 10/10 | タスク固有 |
| Currency (Timeliness) | 5/10 | タスク固有 |

**ファクトチェック結果**:
| 指標 | 値 |
|------|-----|
| 抽出文数 | 3 |
| Correct | 0 |
| Incorrect | 0 |
| Unknown | 2 |
| Partially Correct | 1 |

**問題点**:
- クエリ「What is Swift?」がSWIFT金融ネットワークと誤解釈
- Coverage/Insightが1/10（情報が根本的に誤り）

## エラーハンドリング

Apple SystemLanguageModelは構造化出力で `dictionaryExpected` エラーを返すことがある。各Stepにフォールバックを実装:

```swift
do {
    let response = try await session.respond(generating: Response.self) { ... }
} catch {
    // フォールバック処理で評価を継続
    return fallbackValue
}
```

| Step | フォールバック |
|------|---------------|
| DimensionGeneratorStep | 空配列（一般次元のみで評価継続） |
| DimensionScorerStep | デフォルトスコア 5/10 |
| AdaptiveQualityStep | 次元スコアから導出した評価 |
| StatementExtractorStep | 空配列（ファクトチェックスキップ） |

## 使用方法

```bash
# 評価テストの実行
swift run research-cli test-evaluation "What is Swift?" --limit 3
```

```swift
// プログラムから実行
let qualityStep = AdaptiveQualityStep()
    .session(session)

let result = try await qualityStep.run(
    QualityEvaluationInput(
        task: evaluationTask,
        researchOutput: researchMarkdown
    )
)

print("Quality Score: \(result.normalizedScore)/100")
```

## 実装済み改善

- [x] QueryDisambiguationStep - ドメインコンテキストによるクエリ曖昧性解消
- [x] 各Stepへのドメインコンテキスト伝播（@Contextable/@Context パターン）

## 今後の改善

- [ ] `dictionaryExpected` エラーの根本解決（構造化出力の安定化）
- [ ] FactCheckOrchestratorのタイムアウト対策
- [ ] バッチ評価機能（100タスク一括実行）
- [ ] AutoTuner実装（評価結果からプロンプト自動調整）
- [ ] Cross-judge評価（複数LLMによる評価）
