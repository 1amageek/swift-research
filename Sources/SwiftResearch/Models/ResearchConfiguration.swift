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
/// | `MAX_CONCURRENT` | Number of parallel workers | 4 |
/// | `MAX_URLS` | Maximum URLs to process | 50 |
/// | `KNOWN_FACTS_LIMIT` | Facts shared between workers | 5 |
/// | `CONTENT_MAX_CHARS` | Max content length for review | 1500 |
///
/// ## Example
///
/// ```swift
/// // Use shared instance (reads from environment)
/// let config = ResearchConfiguration.shared
///
/// // Or create custom configuration
/// let config = ResearchConfiguration(
///     maxConcurrent: 8,
///     maxURLs: 100
/// )
/// ```
public struct ResearchConfiguration: Sendable {

    // MARK: - Default Values

    /// Default configuration values.
    public enum Defaults {
        /// Default number of concurrent workers.
        public static let maxConcurrent = 4
        /// Default maximum URLs to process.
        public static let maxURLs = 50
        /// Default number of known facts to share.
        public static let knownFactsLimit = 5
        /// Default maximum content characters for review.
        public static let contentMaxChars = 1500
        /// Whether the LLM supports concurrent requests.
        /// SystemLanguageModel (FoundationModels) does NOT support concurrent requests.
        /// API-based models (Ollama, OpenAI, etc.) typically DO support concurrent requests.
        public static let llmSupportsConcurrency = false
    }

    // MARK: - Properties

    /// Number of parallel workers for crawling.
    public let maxConcurrent: Int

    /// Maximum number of URLs to process per research session.
    public let maxURLs: Int

    /// Number of known facts shared between workers to avoid duplication.
    public let knownFactsLimit: Int

    /// Maximum content length (in characters) sent to LLM for review.
    public let contentMaxChars: Int

    /// Whether the LLM supports concurrent requests.
    ///
    /// - `false` (default): Each worker creates its own session (for SystemLanguageModel/FoundationModels)
    /// - `true`: Workers share a single session (for API-based models like Ollama, OpenAI)
    public let llmSupportsConcurrency: Bool

    // MARK: - Initialization

    /// Creates a configuration by reading from environment variables.
    ///
    /// Falls back to default values for any missing environment variables.
    public init() {
        let env = ProcessInfo.processInfo.environment

        self.maxConcurrent = Self.getInt(from: env, key: EnvironmentVariables.maxConcurrent, default: Defaults.maxConcurrent)
        self.maxURLs = Self.getInt(from: env, key: EnvironmentVariables.maxURLs, default: Defaults.maxURLs)
        self.knownFactsLimit = Self.getInt(from: env, key: EnvironmentVariables.knownFactsLimit, default: Defaults.knownFactsLimit)
        self.contentMaxChars = Self.getInt(from: env, key: EnvironmentVariables.contentMaxChars, default: Defaults.contentMaxChars)
        self.llmSupportsConcurrency = Self.getBool(from: env, key: EnvironmentVariables.llmSupportsConcurrency, default: Defaults.llmSupportsConcurrency)
    }

    /// Creates a configuration with custom values.
    ///
    /// - Parameters:
    ///   - maxConcurrent: Number of parallel workers.
    ///   - maxURLs: Maximum URLs to process.
    ///   - knownFactsLimit: Number of known facts to share.
    ///   - contentMaxChars: Maximum content length for review.
    ///   - llmSupportsConcurrency: Whether LLM supports concurrent requests.
    public init(
        maxConcurrent: Int = Defaults.maxConcurrent,
        maxURLs: Int = Defaults.maxURLs,
        knownFactsLimit: Int = Defaults.knownFactsLimit,
        contentMaxChars: Int = Defaults.contentMaxChars,
        llmSupportsConcurrency: Bool = Defaults.llmSupportsConcurrency
    ) {
        self.maxConcurrent = maxConcurrent
        self.maxURLs = maxURLs
        self.knownFactsLimit = knownFactsLimit
        self.contentMaxChars = contentMaxChars
        self.llmSupportsConcurrency = llmSupportsConcurrency
    }

    // MARK: - Helper Methods

    private static func getInt(from env: [String: String], key: String, default defaultValue: Int) -> Int {
        guard let value = env[key], let intValue = Int(value) else {
            return defaultValue
        }
        return intValue
    }

    private static func getBool(from env: [String: String], key: String, default defaultValue: Bool) -> Bool {
        guard let value = env[key]?.lowercased() else {
            return defaultValue
        }
        return value == "true" || value == "1" || value == "yes"
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
        /// Number of concurrent workers: `MAX_CONCURRENT`
        public static let maxConcurrent = "MAX_CONCURRENT"

        /// Maximum URLs to process: `MAX_URLS`
        public static let maxURLs = "MAX_URLS"

        /// Known facts limit: `KNOWN_FACTS_LIMIT`
        public static let knownFactsLimit = "KNOWN_FACTS_LIMIT"

        /// Maximum content characters: `CONTENT_MAX_CHARS`
        public static let contentMaxChars = "CONTENT_MAX_CHARS"

        /// LLM supports concurrent requests: `LLM_SUPPORTS_CONCURRENCY`
        public static let llmSupportsConcurrency = "LLM_SUPPORTS_CONCURRENCY"
    }
}

// MARK: - CustomStringConvertible

extension ResearchConfiguration: CustomStringConvertible {
    public var description: String {
        """
        ResearchConfiguration:
          maxConcurrent: \(maxConcurrent)
          maxURLs: \(maxURLs)
          knownFactsLimit: \(knownFactsLimit)
          contentMaxChars: \(contentMaxChars)
          llmSupportsConcurrency: \(llmSupportsConcurrency)
        """
    }
}
