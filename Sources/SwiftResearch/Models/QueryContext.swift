import Foundation
import SwiftAgent

/// Context containing the user's query, extracted subject, and reasoning.
///
/// This context is shared across all steps to ensure consistent understanding
/// of what the user wants to know about.
///
/// ## Example
///
/// ```swift
/// let context = QueryContext(
///     query: "京都について調査してください",
///     subject: "京都",
///     reasoning: "「調査」は動作であり主題ではないため、ユーザーが知りたい対象は「京都」です。"
/// )
/// ```
@Contextable
public struct QueryContext: Sendable {
    /// The original user query.
    public let query: String

    /// The main subject/topic extracted from the query.
    public let subject: String

    /// The reasoning explaining why this subject was extracted.
    public let reasoning: String

    public init(query: String, subject: String, reasoning: String) {
        self.query = query
        self.subject = subject
        self.reasoning = reasoning
    }

    /// Creates a fallback context when extraction fails.
    public static func fallback(query: String) -> QueryContext {
        QueryContext(
            query: query,
            subject: query,
            reasoning: "クエリをそのまま主題として使用します。"
        )
    }

    /// The default value for Contextable conformance.
    public static var defaultValue: QueryContext {
        fatalError("QueryContext must be explicitly set via QueryContextContext.withValue()")
    }
}
