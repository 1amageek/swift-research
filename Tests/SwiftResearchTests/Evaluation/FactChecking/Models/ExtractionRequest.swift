import Foundation
import SwiftAgent

/// Input for statement extraction.
///
/// Contains the text to extract verifiable statements from and
/// the maximum number of statements to extract.
public struct ExtractionRequest: Sendable {
    /// Text to extract verifiable statements from.
    public let text: String

    /// Maximum number of statements to extract.
    public let maxStatements: Int

    /// Creates a new extraction request.
    ///
    /// - Parameters:
    ///   - text: The text to extract statements from.
    ///   - maxStatements: Maximum number of statements to extract.
    public init(text: String, maxStatements: Int = 20) {
        self.text = text
        self.maxStatements = maxStatements
    }
}
