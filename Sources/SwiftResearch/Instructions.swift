// Instructions.swift
// SwiftResearch - Common instructions for LLM sessions

import Foundation

/// Common instructions builder for LLM sessions.
///
/// Each Step uses these helpers to build consistent system instructions
/// that include current date/time and common rules.
public enum StepInstructions {

    /// Builds base instructions with common rules.
    ///
    /// - Parameter role: The role description (e.g., "情報収集エージェント")
    /// - Returns: Base instructions string
    public static func base(role: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        let currentDateTime = formatter.string(from: Date())
        let timeZone = TimeZone.current.identifier

        return """
        あなたは\(role)です。

        # 現在の日時
        \(currentDateTime) (\(timeZone))

        # 出力規則
        - 常に有効なJSONオブジェクトで応答する（'{'で開始）
        - 配列フィールドはJSON配列として出力
        - Markdownコードフェンスは含めない

        # 重要: フィールド値の生成規則
        - JSON Schemaのdescriptionは「説明」であり「値」ではない
        - descriptionをそのままコピーして値として使用しないこと
        - 入力から実際の値を抽出・生成すること

        # 行動規則
        - 事実に基づいて回答する
        - 不明な場合は推測せず、その旨を明記する
        """
    }

    /// Instructions for query understanding (extracting subject from query).
    public static var queryUnderstanding: String {
        base(role: "情報収集エージェント") + """


        # タスク
        ユーザーのクエリから主題（subject）を抽出する。
        - 「調査」「教えて」「説明」「検索」等の動作語は主題ではない
        - ユーザーが知りたい対象のみを抽出すること
        """
    }

    /// Instructions for query disambiguation.
    public static var queryDisambiguation: String {
        base(role: "情報収集エージェント") + """


        # タスク
        ドメインコンテキストを考慮してクエリを解釈する。
        - 専門用語は適切に解釈
        - 曖昧な表現は具体化
        """
    }

    /// Instructions for objective analysis (generating keywords and questions).
    public static var objectiveAnalysis: String {
        base(role: "情報収集エージェント") + """


        # タスク
        主題について以下を生成する:
        1. 検索キーワード（英語、検索エンジン向け）
        2. 答えるべき具体的な問い
        3. 情報収集の成功基準
        """
    }

    /// Instructions for content review (evaluating page relevance).
    public static var contentReview: String {
        base(role: "情報収集エージェント") + """


        # タスク
        ページ内容を評価し、関連情報を抽出する。
        - 目的に関連する情報を特定
        - 重要な事実を簡潔に抽出
        - 追加クロールすべきリンクを評価
        """
    }

    /// Instructions for sufficiency check.
    public static var sufficiencyCheck: String {
        base(role: "情報収集エージェント") + """


        # タスク
        収集した情報が目的を達成するのに十分かを判定する。
        - 成功基準との照合
        - 不足している情報の特定
        - 追加キーワードの提案
        """
    }

    /// Instructions for response building.
    public static var responseBuilding: String {
        base(role: "情報収集エージェント") + """


        # タスク
        収集した情報から最終回答を生成する。
        - Markdown形式で構造化
        - 根拠を明示
        - 簡潔で正確な回答
        """
    }
}
