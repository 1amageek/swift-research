import Foundation
import SwiftAgent

/// Verdict for a fact verification.
@Generable
public enum FactVerdict: String, Sendable, Codable, CaseIterable {
    /// The statement is verified as correct.
    case correct = "Correct"

    /// The statement is verified as incorrect.
    case incorrect = "Incorrect"

    /// Unable to determine correctness.
    case unknown = "Unknown"

    /// The statement is partially correct.
    case partiallyCorrect = "Partially Correct"

    /// An error occurred during verification.
    case errorOccurred = "Error Occurred"

    /// Whether this verdict counts as "correct" for accuracy calculation.
    public var isCorrect: Bool {
        self == .correct
    }

    /// Whether this verdict counts as "incorrect" for accuracy calculation.
    public var isIncorrect: Bool {
        self == .incorrect
    }

    /// Whether this verdict represents an error state.
    public var isError: Bool {
        self == .errorOccurred
    }
}

/// Result of verifying a single statement.
public struct FactVerificationResult: Sendable, Identifiable, Codable, Hashable {
    /// Unique identifier.
    public var id: UUID { statement.id }

    /// The statement that was verified.
    public let statement: VerifiableStatement

    /// The verification verdict.
    public let verdict: FactVerdict

    /// Evidence collected for verification.
    public let evidence: [Evidence]

    /// Confidence in the verdict (0.0-1.0).
    public let confidence: Double

    /// Explanation of how the verdict was determined.
    public let explanation: String

    /// The correct information if the statement is incorrect or partially correct.
    /// Only populated when verdict is `.incorrect` or `.partiallyCorrect`.
    public let correction: String?

    /// Creates a new fact verification result.
    ///
    /// - Parameters:
    ///   - statement: The statement that was verified.
    ///   - verdict: The verification verdict.
    ///   - evidence: Evidence collected.
    ///   - confidence: Confidence in the verdict.
    ///   - explanation: Explanation of the verdict.
    ///   - correction: The correct information if incorrect/partially correct.
    public init(
        statement: VerifiableStatement,
        verdict: FactVerdict,
        evidence: [Evidence],
        confidence: Double,
        explanation: String,
        correction: String? = nil
    ) {
        self.statement = statement
        self.verdict = verdict
        self.evidence = evidence
        self.confidence = max(0.0, min(1.0, confidence))
        self.explanation = explanation
        self.correction = correction
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(statement.id)
    }

    public static func == (lhs: FactVerificationResult, rhs: FactVerificationResult) -> Bool {
        lhs.statement.id == rhs.statement.id
    }
}

// MARK: - CustomStringConvertible

extension FactVerificationResult: CustomStringConvertible {
    public var description: String {
        "[\(verdict.rawValue)] \(statement.text.prefix(40))... (conf: \(String(format: "%.2f", confidence)))"
    }
}

/// Overall result of fact-checking a research output.
public struct FactCheckResult: Sendable, Codable {
    /// All verification results.
    public let verifications: [FactVerificationResult]

    /// Total number of statements checked.
    public let totalStatements: Int

    /// Number of correct statements.
    public let correctCount: Int

    /// Number of incorrect statements.
    public let incorrectCount: Int

    /// Number of unknown/unverifiable statements.
    public let unknownCount: Int

    /// Number of partially correct statements.
    public let partiallyCorrectCount: Int

    /// Number of statements that failed verification due to errors.
    public let errorCount: Int

    /// Factual accuracy percentage (correct / (correct + incorrect)).
    public let accuracy: Double

    /// Average confidence across all verifications.
    public let averageConfidence: Double

    /// Creates a new fact check result.
    ///
    /// - Parameter verifications: All verification results.
    public init(verifications: [FactVerificationResult]) {
        self.verifications = verifications
        self.totalStatements = verifications.count

        self.correctCount = verifications.filter { $0.verdict == .correct }.count
        self.incorrectCount = verifications.filter { $0.verdict == .incorrect }.count
        self.unknownCount = verifications.filter { $0.verdict == .unknown }.count
        self.partiallyCorrectCount = verifications.filter { $0.verdict == .partiallyCorrect }.count
        self.errorCount = verifications.filter { $0.verdict == .errorOccurred }.count

        // Accuracy: correct / (correct + incorrect), ignoring unknown
        let verifiableCount = correctCount + incorrectCount
        self.accuracy = verifiableCount > 0
            ? Double(correctCount) / Double(verifiableCount) * 100.0
            : 0.0

        // Average confidence
        self.averageConfidence = verifications.isEmpty
            ? 0.0
            : verifications.reduce(0.0) { $0 + $1.confidence } / Double(verifications.count)
    }

    /// Verifications filtered by verdict.
    public func verifications(with verdict: FactVerdict) -> [FactVerificationResult] {
        verifications.filter { $0.verdict == verdict }
    }

    /// High-confidence incorrect statements (most likely actual errors).
    public var highConfidenceErrors: [FactVerificationResult] {
        verifications.filter { $0.verdict == .incorrect && $0.confidence >= 0.7 }
    }

    /// All verifications that have corrections (incorrect or partially correct with correction provided).
    public var verificationsWithCorrections: [FactVerificationResult] {
        verifications.filter { $0.correction != nil }
    }

    /// Summary of all errors with their corrections for feedback analysis.
    public var errorSummary: [(statement: String, correction: String)] {
        verifications.compactMap { result in
            guard let correction = result.correction else { return nil }
            return (statement: result.statement.text, correction: correction)
        }
    }
}

// MARK: - CustomStringConvertible

extension FactCheckResult: CustomStringConvertible {
    public var description: String {
        var result = "Accuracy: \(String(format: "%.1f", accuracy))% (\(correctCount)/\(correctCount + incorrectCount) verified, \(unknownCount) unknown"
        if errorCount > 0 {
            result += ", \(errorCount) errors"
        }
        result += ")"
        return result
    }
}
