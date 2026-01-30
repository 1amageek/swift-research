import Foundation

/// A quality evaluation dimension with scoring rubric.
///
/// Dimensions can be general (applicable to all tasks) or task-specific
/// (generated dynamically based on task requirements).
public struct QualityDimension: Sendable, Identifiable, Codable, Hashable {
    /// Unique identifier for the dimension.
    public let id: UUID

    /// Name of the dimension.
    public let name: String

    /// Description of what this dimension measures.
    public let dimensionDescription: String

    /// Weight of this dimension in the overall score (0.0-1.0).
    public let weight: Double

    /// Whether this is a general (true) or task-specific (false) dimension.
    public let isGeneral: Bool

    /// Scoring rubric: maps scores (1-10) to descriptions.
    public let rubric: [Int: String]

    /// Creates a new quality dimension.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - name: Name of the dimension.
    ///   - dimensionDescription: Description of what it measures.
    ///   - weight: Weight in overall score.
    ///   - isGeneral: Whether this is a general dimension.
    ///   - rubric: Scoring rubric.
    public init(
        id: UUID = UUID(),
        name: String,
        dimensionDescription: String,
        weight: Double,
        isGeneral: Bool,
        rubric: [Int: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.dimensionDescription = dimensionDescription
        self.weight = weight
        self.isGeneral = isGeneral
        self.rubric = rubric.isEmpty ? Self.defaultRubric : rubric
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: QualityDimension, rhs: QualityDimension) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Default Rubric

    /// Default scoring rubric for dimensions without a custom one.
    public static let defaultRubric: [Int: String] = [
        1: "Completely inadequate",
        2: "Very poor",
        3: "Poor",
        4: "Below average",
        5: "Average",
        6: "Above average",
        7: "Good",
        8: "Very good",
        9: "Excellent",
        10: "Outstanding"
    ]
}

// MARK: - General Dimensions

extension QualityDimension {
    /// Coverage: How comprehensively the response addresses all aspects.
    public static let coverage = QualityDimension(
        name: "Coverage",
        dimensionDescription: "How comprehensively does the response address all aspects of the query?",
        weight: 0.25,
        isGeneral: true,
        rubric: [
            1: "Misses almost all key aspects",
            3: "Covers only a few aspects superficially",
            5: "Covers main aspects but misses important details",
            7: "Covers most aspects with reasonable depth",
            9: "Comprehensive coverage of all aspects",
            10: "Exhaustive coverage with unexpected valuable additions"
        ]
    )

    /// Insight: Whether the response provides valuable insights beyond surface-level.
    public static let insight = QualityDimension(
        name: "Insight",
        dimensionDescription: "Does the response provide valuable insights beyond surface-level information?",
        weight: 0.25,
        isGeneral: true,
        rubric: [
            1: "No insights, purely superficial",
            3: "Minimal insights, mostly obvious information",
            5: "Some useful insights but nothing remarkable",
            7: "Good insights that add meaningful value",
            9: "Deep insights that significantly enhance understanding",
            10: "Exceptional insights that reveal non-obvious patterns or implications"
        ]
    )

    /// Instruction Following: How well the response follows given instructions.
    public static let instructionFollowing = QualityDimension(
        name: "Instruction Following",
        dimensionDescription: "How well does the response follow the given instructions and requirements?",
        weight: 0.25,
        isGeneral: true,
        rubric: [
            1: "Completely ignores instructions",
            3: "Follows some instructions but misses key requirements",
            5: "Follows most instructions with minor deviations",
            7: "Follows all instructions accurately",
            9: "Follows all instructions perfectly with appropriate interpretation",
            10: "Exceeds instructions while perfectly meeting all requirements"
        ]
    )

    /// Clarity: How well-organized and easy to understand the response is.
    public static let clarity = QualityDimension(
        name: "Clarity",
        dimensionDescription: "Is the response well-organized and easy to understand?",
        weight: 0.25,
        isGeneral: true,
        rubric: [
            1: "Incomprehensible or extremely disorganized",
            3: "Confusing structure, hard to follow",
            5: "Understandable but could be better organized",
            7: "Well-organized and clear",
            9: "Exceptionally clear with excellent structure",
            10: "Perfect clarity with intuitive organization and flow"
        ]
    )

    /// All general dimensions used for every evaluation.
    public static let generalDimensions: [QualityDimension] = [
        .coverage,
        .insight,
        .instructionFollowing,
        .clarity
    ]
}

// MARK: - CustomStringConvertible

extension QualityDimension: CustomStringConvertible {
    public var description: String {
        "\(name) (weight: \(String(format: "%.2f", weight)), \(isGeneral ? "general" : "task-specific"))"
    }
}
