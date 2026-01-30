import Foundation

/// Score for a single quality dimension.
public struct DimensionScore: Sendable, Codable, Hashable {
    /// The dimension that was scored.
    public let dimension: QualityDimension

    /// The score (1-10).
    public let score: Int

    /// Reasoning for the score.
    public let reasoning: String

    /// Specific evidence from the response supporting the score.
    public let evidence: [String]

    /// Improvement suggestions for this dimension.
    public let suggestions: [String]

    /// Creates a new dimension score.
    ///
    /// - Parameters:
    ///   - dimension: The dimension that was scored.
    ///   - score: The score (1-10).
    ///   - reasoning: Reasoning for the score.
    ///   - evidence: Supporting evidence.
    ///   - suggestions: Improvement suggestions.
    public init(
        dimension: QualityDimension,
        score: Int,
        reasoning: String,
        evidence: [String],
        suggestions: [String] = []
    ) {
        self.dimension = dimension
        self.score = max(1, min(10, score)) // Clamp to 1-10
        self.reasoning = reasoning
        self.evidence = evidence
        self.suggestions = suggestions
    }

    /// The weighted score (score * dimension.weight).
    public var weightedScore: Double {
        Double(score) * dimension.weight
    }
}

// MARK: - CustomStringConvertible

extension DimensionScore: CustomStringConvertible {
    public var description: String {
        "\(dimension.name): \(score)/10"
    }
}

/// Overall quality evaluation result.
public struct QualityEvaluationResult: Sendable, Codable {
    /// Scores for each evaluated dimension.
    public let dimensionScores: [DimensionScore]

    /// Weighted average score (1-10 scale).
    public let weightedAverageScore: Double

    /// Normalized score (0-100 scale).
    public let normalizedScore: Double

    /// Overall summary of the quality evaluation.
    public let summary: String

    /// Identified strengths of the response.
    public let strengths: [String]

    /// Identified weaknesses of the response.
    public let weaknesses: [String]

    /// Suggested improvements.
    public let improvements: [String]

    /// Creates a new quality evaluation result.
    ///
    /// - Parameters:
    ///   - dimensionScores: Scores for each dimension.
    ///   - summary: Overall summary of the evaluation.
    ///   - strengths: Identified strengths.
    ///   - weaknesses: Identified weaknesses.
    ///   - improvements: Suggested improvements.
    public init(
        dimensionScores: [DimensionScore],
        summary: String = "",
        strengths: [String] = [],
        weaknesses: [String] = [],
        improvements: [String] = []
    ) {
        self.dimensionScores = dimensionScores
        self.summary = summary
        self.strengths = strengths
        self.weaknesses = weaknesses
        self.improvements = improvements

        // Calculate weighted average
        let totalWeight = dimensionScores.reduce(0.0) { $0 + $1.dimension.weight }
        if totalWeight > 0 {
            self.weightedAverageScore = dimensionScores.reduce(0.0) { $0 + $1.weightedScore } / totalWeight
        } else {
            self.weightedAverageScore = 0.0
        }

        // Normalize to 0-100 scale
        self.normalizedScore = (weightedAverageScore / 10.0) * 100.0
    }

    /// Score for a specific dimension by name.
    public func score(for dimensionName: String) -> DimensionScore? {
        dimensionScores.first { $0.dimension.name == dimensionName }
    }

    /// General dimension scores only.
    public var generalScores: [DimensionScore] {
        dimensionScores.filter { $0.dimension.isGeneral }
    }

    /// Task-specific dimension scores only.
    public var taskSpecificScores: [DimensionScore] {
        dimensionScores.filter { !$0.dimension.isGeneral }
    }
}

// MARK: - CustomStringConvertible

extension QualityEvaluationResult: CustomStringConvertible {
    public var description: String {
        let scores = dimensionScores.map { "\($0.dimension.name): \($0.score)" }.joined(separator: ", ")
        return "Quality: \(String(format: "%.1f", normalizedScore))/100 [\(scores)]"
    }
}
