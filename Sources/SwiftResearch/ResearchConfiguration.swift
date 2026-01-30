import Foundation

/// Global configuration for SwiftResearch.
///
/// Configuration values can be set via environment variables or programmatically.
/// Environment variables take precedence over default values.
///
/// ## Environment Variables
///
/// | Variable | Description | Default |
/// |----------|-------------|---------|
/// | `MAX_URLS` | Maximum URLs to process | 50 |
///
/// ## Example
///
/// ```swift
/// // Use shared instance (reads from environment)
/// let config = ResearchConfiguration.shared
///
/// // Or create custom configuration
/// let config = ResearchConfiguration(maxURLs: 100)
/// ```
public struct ResearchConfiguration: Sendable {

    // MARK: - Default Values

    /// Default configuration values.
    public enum Defaults {
        /// Default maximum URLs to process.
        public static let maxURLs = 50
    }

    // MARK: - Properties

    /// Maximum number of URLs to process per research session.
    public let maxURLs: Int

    // MARK: - Initialization

    /// Creates a configuration by reading from environment variables.
    ///
    /// Falls back to default values for any missing environment variables.
    public init() {
        let env = ProcessInfo.processInfo.environment
        self.maxURLs = Self.getInt(from: env, key: EnvironmentVariables.maxURLs, default: Defaults.maxURLs)
    }

    /// Creates a configuration with custom values.
    ///
    /// - Parameters:
    ///   - maxURLs: Maximum URLs to process.
    public init(maxURLs: Int = Defaults.maxURLs) {
        self.maxURLs = maxURLs
    }

    // MARK: - Helper Methods

    private static func getInt(from env: [String: String], key: String, default defaultValue: Int) -> Int {
        guard let value = env[key], let intValue = Int(value) else {
            return defaultValue
        }
        return intValue
    }

    // MARK: - Shared Instance

    /// The shared configuration instance.
    ///
    /// Reads configuration from environment variables at first access.
    public static let shared = ResearchConfiguration()
}

// MARK: - Environment Variable Names

extension ResearchConfiguration {
    /// Environment variable names for configuration.
    public enum EnvironmentVariables {
        /// Maximum URLs to process: `MAX_URLS`
        public static let maxURLs = "MAX_URLS"
    }
}

// MARK: - CustomStringConvertible

extension ResearchConfiguration: CustomStringConvertible {
    public var description: String {
        """
        ResearchConfiguration:
          maxURLs: \(maxURLs)
        """
    }
}
