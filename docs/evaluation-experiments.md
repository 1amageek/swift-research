# Evaluation Experiments

## 実験概要

SwiftResearch の評価フレームワークにおける品質スコア改善実験の記録。

## ベースライン (2025-01-22)

**モデル:** `lfm2.5-thinking` (Ollama)
**テストクエリ:** "What is the current population of Tokyo?"
**ドメインコンテキスト:** Software development, AI, hardware, cybersecurity

### ベースラインスコア

| メトリクス | スコア |
|-----------|--------|
| Overall | 80.2/100 |
| Quality | 67.0/100 |
| Factual Accuracy | 100% |

| 次元 | スコア |
|------|--------|
| Coverage | 7/10 |
| Insight | 5/10 |
| Instruction Following | 7/10 |
| Clarity | 7/10 |
| Technical Accuracy | 7/10 |

### 課題

- **Insight スコアが低い (5/10)**: 事実の羅列に留まり、分析・洞察が不足
- **成功基準が事実偏重**: 「背景・理由・意味」の収集を促していない

---

## 実験1: 成功基準プロンプトの改善

### 仮説

成功基準を `questions` と連携させ、「背景・理由」も収集対象とすることで Insight スコアが向上する。

### 変更内容

**ObjectiveAnalysisStep.swift** のプロンプト変更:

```diff
  ### 3. 成功基準（successCriteria）
- 情報収集が十分と判断するための具体的な条件を詳細にリスト化。
- - 目的を達成するために必要な情報項目を全て列挙
- - 具体的な属性名を明記する
+ 「ユーザーの質問」に回答するために収集すべき情報の条件をリスト化。
+ - 具体的な事実・データ（数値、日付、名称など）
+ - その事実の背景や理由
+ - 上記の問い（questions）への回答に必要な情報
```

### 結果

6回の実行結果:

| 実行 | Overall | Quality | Insight | Coverage | 備考 |
|------|---------|---------|---------|----------|------|
| ベースライン | 80.2 | 67.0 | 5 | 7 | 変更前 |
| 1回目 | 62.3 | 37.1 | 3 | 4 | LLM異常応答 |
| 2回目 | 80.2 | 67.0 | **7** | 5 | Insight改善 |
| 3回目 | 61.4 | 35.7 | - | 5 | LLM異常 |
| 4回目 | **82.7** | **71.2** | **7** | 5 | 最良結果 |
| 5回目 | 55.3 | 70.0 | **7** | 7 | Fact低下 |
| 6回目 | 73.9 | 56.5 | 2 | 3 | 低品質 |

### 観察

**ポジティブな傾向:**
- 正常動作時、Insight は 5→7 に改善 (+40%)
- Quality スコアも 67→70-71 に改善傾向

**問題点:**
1. **高いばらつき**: LLM応答品質が不安定
2. **ドメインコンテキスト不一致**: テスト用コンテキストがクエリと合わない
3. **メタ応答**: LLMが時々「JSON形式で提供しました」のようなメタ応答を生成

### 分析

LLM応答のばらつき原因:

1. **Instructions不足**: プロンプトが「何をすべきか」を十分に定義していない
2. **出力形式の混乱**: JSON形式要求とコンテンツ生成要求が混同される
3. **コンテキスト干渉**: ドメインコンテキストが無関係なクエリに影響

---

## 実験2: Session独立化 (2026-01-22)

### 背景

実験1のプロンプト改善後、スコアのばらつきが大きかった:
- Overall: 74.8 / 46.3 (2回の実行で大きく異なる)
- Quality: 58.0 / 32.8

### 問題の原因

**同一Sessionの使い回しによるコンテキスト蓄積:**

| Phase | 出力形式 | Session |
|-------|---------|---------|
| Phase 0 | テキスト/JSON | 共有 |
| Phase 1 | JSON | 共有 |
| Phase 3 | JSON | 独立（並列処理） |
| Phase 4 | JSON | 共有 |
| Phase 5 | JSON (Markdown内包) | 共有 |

Phase 5の時点で、LLMは以下のコンテキストを見ていた:
```
[System Prompt]
[Phase 1 Prompt] → {"keywords": [...], "questions": [...], ...}
[Phase 4 Prompt] → {"isSufficient": false, ...}
[Phase 5 Prompt] ← JSONパターンに引っ張られる
```

### 変更内容

**SearchOrchestratorStep.swift:**

1. `createStepSession()` メソッドを追加:
```swift
private func createStepSession() -> LanguageModelSession {
    if let factory = sessionFactory {
        return factory()
    }
    return session
}
```

2. 各Phaseで独立したSessionを使用:
```swift
// Phase 1
let analysis = try await SessionContext.$current.withValue(createStepSession()) {
    try await SearchConfigurationContext.withValue(configuration) {
        try await ObjectiveAnalysisStep(progressContinuation: progressContinuation)
            .run(analysisInput)
    }
}

// Phase 4, 5も同様に変更
```

**変更対象:**
- Phase 0: QueryDisambiguationStep, extractBasicInfo
- Phase 1: ObjectiveAnalysisStep
- Phase 4: SufficiencyCheckStep
- Phase 5: ResponseBuildingStep

### 結果

| 状態 | Overall | Quality | Insight | Coverage | 分散 |
|------|---------|---------|---------|----------|------|
| ベースライン | 80.2 | 67.0 | 5 | 7 | - |
| 実験1（Session共有） | 74.8 / 46.3 | 58.0 / 32.8 | - | - | **高** |
| **実験2（Session独立）** | **82.0 / 82.0** | **70.0 / 70.0** | 7 | 7 | **なし** |

### 詳細スコア (実験2)

| 次元 | スコア |
|------|--------|
| Coverage | 7/10 |
| Insight | 7/10 |
| Instruction Following | 7/10 |
| Clarity | 7/10 |
| Technical Accuracy | 7/10 |
| Factual Accuracy | 100% |

### 観察

1. **一貫性の大幅改善**: 2回の実行で完全に同じスコア
2. **Overall改善**: 80.2 → 82.0 (+1.8)
3. **Quality改善**: 67.0 → 70.0 (+3.0)
4. **Insight維持**: ベースラインの5から7に改善を維持

### 結論

Session独立化により:
- 前のPhaseのJSON応答パターンがPhase 5に影響しなくなった
- 各Stepが独立して動作し、出力形式の混乱が解消
- スコアの安定性が大幅に向上

---

## 次のステップ

### 完了

- [x] LLM傾向テストの作成
- [x] Instructions強化（Claude Code形式のプロンプト構造）
- [x] Session独立化

### TODO

1. **さらなるQuality改善**: 現在70.0 → 目標80.0
2. **Insight深化**: 分析・洞察の質を向上
3. **プロンプトの継続改善**: 構造化出力の精度向上

### 改善候補

| 優先度 | 対象 | 改善内容 |
|--------|------|----------|
| 1 | ResponseBuildingStep | 回答の深さ・分析力を向上 |
| 2 | ObjectiveAnalysisStep | より具体的な成功基準の生成 |
| 3 | ContentReviewStep | 抽出情報の質向上 |

---

## 参考

- AMD Framework (arXiv:2502.08557): Socratic質問分解の理論的基盤
- Agentic RAG (arXiv:2501.09136): 反省・計画パターン
- The Prompt Report (arXiv:2406.06608): 58のプロンプト技法の体系的分類
