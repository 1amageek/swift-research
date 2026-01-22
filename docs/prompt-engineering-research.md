# プロンプトエンジニアリング研究まとめ

## 参考文献

1. [The Prompt Report](https://arxiv.org/abs/2406.06608) - 58のプロンプト技法の分類
2. [Systematic Survey of Prompt Engineering](https://arxiv.org/abs/2402.07927) - タスク/応用別の整理
3. [Automatic Prompt Optimization Survey](https://arxiv.org/abs/2502.16923) - APOの体系化
4. [TextGrad](https://arxiv.org/abs/2406.07496) - テキスト勾配によるプロンプト最適化
5. [RiOT](https://arxiv.org/abs/2506.16389) - Residual Optimization Tree
6. [DSPy](https://arxiv.org/abs/2310.03714) - 宣言的プロンプトコンパイル
7. [Chain of Guidance](https://arxiv.org/html/2502.15924v1) - 一貫性向上技法
8. [Structured Outputs Evaluation](https://huggingface.co/blog/evaluation-structured-outputs) - 構造化出力の評価

---

## 1. 一貫性向上のための技法

### 問題: LLM出力のばらつき
- プロンプト形式の微小な変更で性能が~10ポイント変動
- Few-shot例の順序変更で~3ポイント変動
- モデルランキングがプロンプト形式で逆転することも

### 解決策

#### A. 構造化出力（Structured Generation）
- 正規表現やJSON Schemaで出力形式を制約
- 結果: **ばらつき大幅減少、スコア向上**

```
GSM8K実験結果:
- 1-shot構造化 = 5-shot非構造化の性能
- モデル間ランキングが安定
```

#### B. 温度・サンプリング設定
```
一貫性重視の設定:
- Temperature: ≤ 0.3（低創造性、決定論的）
- Top-K: 50（低品質トークン排除）
- Top-P: 0.9（多様性と制御のバランス）
```

#### C. Self-Consistency（多数決）
- 同じプロンプトで複数回生成
- 多数決で最終回答を決定
- 推論精度が向上

#### D. Chain of Guidance (CoG)
- パラフレーズ生成 → 予備回答 → 回答ランキング
- 一貫性が最大49%向上
- 回答空間を制約することで幻覚を抑制

---

## 2. 構造化出力のベストプラクティス

### JSON出力の注意点

**長所:**
- 99%以上のスキーマ準拠率
- パースエラー大幅削減
- 統合コード60%削減

**短所:**
- モデルがJSON構文を見ると「技術モード」に切り替わる
- 創造的タスクの品質低下
- トークン効率が悪い（XMLやMarkdownより非効率）

### 推奨アプローチ

```
1. API-native機能を優先（OpenAI/Anthropic の JSON mode）
2. シンプルなスキーマから始める
3. 明確なフィールド名を使用
4. プロンプト内に例を含める（1-shot）
5. バリデーションを実装（Pydantic/Zod相当）
```

### 代替: XML形式
- Claudeが好むフォーマット
- タグベースで視覚的に区切り明確
- トークン効率が良い

---

## 3. プロンプト最適化技法

### TextGrad: テキスト勾配
- 数値勾配の代わりにLLMのテキストフィードバックを使用
- PyTorch風のAPIで自動最適化
- 結果: GPT-4o QA精度 51%→55%、LeetCode-Hard 20%向上

### RiOT: Residual Optimization Tree
- テキスト勾配で反復的にプロンプト改善
- 意味ドリフト対策: テキスト残差接続
- Perplexityベースの候補選択

### DSPy: 宣言的コンパイル
- プロンプトを「モジュール」として定義
- コンパイラが自動でデモ収集・最適化
- 結果: 標準few-shotより25-65%向上（数分のコンパイルで）

---

## 4. SwiftResearchへの適用

### 現在の課題
1. **Insight スコア低い (5/10)**: 分析・洞察が不足
2. **LLM応答のばらつき**: 同じプロンプトで異なる結果
3. **メタ応答**: 「JSONで提供しました」のような不要な応答

### 改善方向性

#### Phase 1: ObjectiveAnalysisStep

**現状のプロンプト問題:**
- 成功基準が事実偏重
- 問い(questions)と成功基準(successCriteria)の連携不足

**改善案:**

```
1. 出力制約の強化
   - JSON Schemaを明示的に定義
   - 各フィールドの目的と制約を記述

2. Chain of Thought誘導
   - 「まず目的を分析し、次に問いを導出...」のステップ指示

3. 例示の追加（1-shot）
   - 期待する出力形式を1例だけ示す
   - 具体的な値は避け、構造のみ示す
```

#### Phase 5: ResponseBuildingStep

**改善案:**

```
1. Chain of Guidance適用
   - 収集情報から複数の回答候補を生成
   - 最も一貫した回答を選択

2. 構造化指示
   - 回答構成を明示（導入→事実→分析→結論）
   - 各セクションの要件を定義
```

### 実装優先度

| 優先度 | 施策 | 期待効果 |
|--------|------|----------|
| 1 | JSON Schema明示化 | ばらつき削減 |
| 2 | 1-shot例示追加 | 形式一貫性向上 |
| 3 | CoT誘導追加 | Insight向上 |
| 4 | 温度設定最適化 | ばらつき削減 |

---

## 5. 評価プロトコル

### 一貫性評価
```
1. 同じ入力で5回実行
2. 出力の標準偏差を計測
3. 構造化vs非構造化を比較
```

### 品質評価
```
1. 複数n-shot設定でテスト (1-5)
2. 例の順序をシャッフル
3. 平均精度と分散の両方を報告
```

---

## 参考リンク

- [Structured Prompting with JSON](https://medium.com/@vishal.dutt.data.architect/structured-prompting-with-json-the-engineering-path-to-reliable-llms-2c0cb1b767cf)
- [5 Tips for Consistent LLM Prompts](https://latitude-blog.ghost.io/blog/5-tips-for-consistent-llm-prompts/)
- [Outlines Library](https://github.com/outlines-dev/outlines) - 構造化生成ライブラリ
