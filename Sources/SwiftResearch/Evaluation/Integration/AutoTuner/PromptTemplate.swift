import Foundation

// MARK: - Tunable Phase

/// Phases of the SwiftResearch pipeline that can be tuned.
public enum TunablePhase: String, Sendable, Codable, CaseIterable {
    case objectiveAnalysis = "Phase 1: Objective Analysis"
    case contentReview = "Phase 3: Content Review"
    case sufficiencyCheck = "Phase 4: Sufficiency Check"
    case responseBuilding = "Phase 5: Response Building"
}

// MARK: - Parameter Type

/// Types of parameters that can be tuned.
public enum ParameterType: String, Sendable, Codable {
    case string
    case integer
    case float
    case boolean
    case stringArray
}

// MARK: - Prompt Parameter

/// A tunable parameter in a prompt template.
public struct PromptParameter: Sendable, Codable, Hashable {
    /// Parameter name.
    public let name: String

    /// Parameter type.
    public let type: ParameterType

    /// Description of what this parameter controls.
    public let description: String

    /// Minimum value (for numeric types).
    public let minValue: Double?

    /// Maximum value (for numeric types).
    public let maxValue: Double?

    /// Available options (for string type with fixed options).
    public let options: [String]?

    /// Default value as string.
    public let defaultValue: String

    /// Creates a new prompt parameter.
    public init(
        name: String,
        type: ParameterType,
        description: String,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        options: [String]? = nil,
        defaultValue: String
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.minValue = minValue
        self.maxValue = maxValue
        self.options = options
        self.defaultValue = defaultValue
    }

    /// Creates an integer parameter.
    public static func integer(
        _ name: String,
        description: String,
        range: ClosedRange<Int>,
        defaultValue: Int
    ) -> PromptParameter {
        PromptParameter(
            name: name,
            type: .integer,
            description: description,
            minValue: Double(range.lowerBound),
            maxValue: Double(range.upperBound),
            defaultValue: String(defaultValue)
        )
    }

    /// Creates a float parameter.
    public static func float(
        _ name: String,
        description: String,
        range: ClosedRange<Double>,
        defaultValue: Double
    ) -> PromptParameter {
        PromptParameter(
            name: name,
            type: .float,
            description: description,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            defaultValue: String(defaultValue)
        )
    }

    /// Creates a boolean parameter.
    public static func boolean(
        _ name: String,
        description: String,
        defaultValue: Bool
    ) -> PromptParameter {
        PromptParameter(
            name: name,
            type: .boolean,
            description: description,
            defaultValue: String(defaultValue)
        )
    }

    /// Creates a string parameter with options.
    public static func string(
        _ name: String,
        description: String,
        options: [String],
        defaultValue: String
    ) -> PromptParameter {
        PromptParameter(
            name: name,
            type: .string,
            description: description,
            options: options,
            defaultValue: defaultValue
        )
    }
}

// MARK: - Prompt Template

/// A parameterized prompt template for a research phase.
public struct PromptTemplate: Sendable, Codable {
    /// The tunable phase this template is for.
    public let phase: TunablePhase

    /// Base prompt with parameter placeholders (e.g., {{paramName}}).
    public let basePrompt: String

    /// Available parameters for this template.
    public let parameters: [PromptParameter]

    /// Current parameter values.
    public var currentValues: [String: String]

    /// Creates a new prompt template.
    public init(
        phase: TunablePhase,
        basePrompt: String,
        parameters: [PromptParameter],
        currentValues: [String: String]? = nil
    ) {
        self.phase = phase
        self.basePrompt = basePrompt
        self.parameters = parameters

        // Initialize with default values if not provided
        if let currentValues = currentValues {
            self.currentValues = currentValues
        } else {
            self.currentValues = Dictionary(
                uniqueKeysWithValues: parameters.map { ($0.name, $0.defaultValue) }
            )
        }
    }

    /// Renders the prompt with current parameter values.
    public func render() -> String {
        var result = basePrompt
        for (name, value) in currentValues {
            result = result.replacingOccurrences(of: "{{\(name)}}", with: value)
        }
        return result
    }

    /// Creates a copy with updated parameter value.
    public func with(_ name: String, value: String) -> PromptTemplate {
        var newValues = currentValues
        newValues[name] = value
        return PromptTemplate(
            phase: phase,
            basePrompt: basePrompt,
            parameters: parameters,
            currentValues: newValues
        )
    }
}

// MARK: - Prompt Version

/// A versioned snapshot of prompt parameters with evaluation score.
public struct PromptVersion: Sendable, Codable, Identifiable {
    /// Unique identifier.
    public let id: UUID

    /// Version number.
    public let version: Int

    /// Timestamp when this version was created.
    public let timestamp: Date

    /// Parameter values for this version.
    public let parameters: [String: String]

    /// Evaluation score achieved with this version.
    public let evaluationScore: Double

    /// Description of changes in this version.
    public let changeDescription: String

    /// Creates a new prompt version.
    public init(
        id: UUID = UUID(),
        version: Int,
        timestamp: Date = Date(),
        parameters: [String: String],
        evaluationScore: Double,
        changeDescription: String
    ) {
        self.id = id
        self.version = version
        self.timestamp = timestamp
        self.parameters = parameters
        self.evaluationScore = evaluationScore
        self.changeDescription = changeDescription
    }
}
