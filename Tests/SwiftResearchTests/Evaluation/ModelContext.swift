// ModelContext.swift
// SwiftResearch - Context for passing LanguageModel through TaskLocal

import Foundation
import SwiftAgent

/// Context for passing LanguageModel through TaskLocal.
///
/// This allows Steps to access the language model without explicit parameter passing.
///
/// ## Usage
///
/// ```swift
/// // At orchestrator level:
/// try await withContext(ModelContext.self, value: ModelContext(model)) {
///     try await QueryUnderstandingStep().run(query)
/// }
///
/// // In Step:
/// struct QueryUnderstandingStep: Step {
///     @Context var modelContext: ModelContext
///
///     func run(...) {
///         let session = LanguageModelSession(
///             model: modelContext.model,
///             instructions: Self.instructions
///         )
///     }
/// }
/// ```
@Contextable
public struct ModelContext: Sendable {
    /// The language model instance.
    public let model: any LanguageModel

    public init(_ model: some LanguageModel) {
        self.model = model
    }

    /// Default value - will crash if not set.
    public static var defaultValue: ModelContext {
        fatalError("ModelContext must be set via withContext(ModelContext.self, value:)")
    }
}
