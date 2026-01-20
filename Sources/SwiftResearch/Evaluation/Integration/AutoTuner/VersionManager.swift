import Foundation
import Synchronization

// MARK: - VersionManager

/// Manages prompt template versions with support for rollback.
///
/// Maintains a history of prompt versions with their associated evaluation scores,
/// allowing rollback to previous versions if performance degrades.
public final class VersionManager: Sendable {
    /// Storage for prompt versions.
    private let storage: Mutex<VersionStorage>

    /// Maximum number of versions to retain.
    public let maxVersions: Int

    /// Degradation threshold triggering automatic rollback.
    public let degradationThreshold: Double

    /// Creates a new version manager.
    ///
    /// - Parameters:
    ///   - maxVersions: Maximum versions to retain.
    ///   - degradationThreshold: Threshold for automatic rollback.
    public init(maxVersions: Int = 10, degradationThreshold: Double = 0.05) {
        self.maxVersions = maxVersions
        self.degradationThreshold = degradationThreshold
        self.storage = Mutex(VersionStorage())
    }

    // MARK: - Version Management

    /// Commits a new version of prompt parameters.
    ///
    /// - Parameters:
    ///   - parameters: The parameter values.
    ///   - evaluationScore: The evaluation score achieved.
    ///   - changeDescription: Description of changes.
    /// - Returns: The created version.
    @discardableResult
    public func commit(
        parameters: [String: String],
        evaluationScore: Double,
        changeDescription: String
    ) -> PromptVersion {
        storage.withLock { storage in
            let version = PromptVersion(
                version: storage.nextVersion,
                parameters: parameters,
                evaluationScore: evaluationScore,
                changeDescription: changeDescription
            )

            storage.versions.append(version)
            storage.nextVersion += 1

            // Trim old versions
            if storage.versions.count > maxVersions {
                storage.versions.removeFirst(storage.versions.count - maxVersions)
            }

            return version
        }
    }

    /// Gets the current (latest) version.
    public var currentVersion: PromptVersion? {
        storage.withLock { $0.versions.last }
    }

    /// Gets a specific version by number.
    ///
    /// - Parameter versionNumber: The version number.
    /// - Returns: The version if found.
    public func version(_ versionNumber: Int) -> PromptVersion? {
        storage.withLock { storage in
            storage.versions.first { $0.version == versionNumber }
        }
    }

    /// Gets all versions.
    public var allVersions: [PromptVersion] {
        storage.withLock { $0.versions }
    }

    // MARK: - Rollback

    /// Rolls back to a specific version.
    ///
    /// - Parameter versionNumber: The version to roll back to.
    /// - Returns: The rolled-back version, or nil if not found.
    public func rollback(to versionNumber: Int) -> PromptVersion? {
        storage.withLock { storage in
            guard let targetIndex = storage.versions.firstIndex(where: { $0.version == versionNumber }) else {
                return nil
            }

            // Remove all versions after the target
            storage.versions.removeSubrange((targetIndex + 1)...)

            return storage.versions.last
        }
    }

    /// Rolls back to the previous version.
    ///
    /// - Returns: The previous version, or nil if no previous version exists.
    public func rollbackToPrevious() -> PromptVersion? {
        storage.withLock { storage in
            guard storage.versions.count >= 2 else {
                return nil
            }

            storage.versions.removeLast()
            return storage.versions.last
        }
    }

    /// Automatically rolls back if the new score is significantly worse.
    ///
    /// - Parameters:
    ///   - newScore: The new evaluation score.
    ///   - previousScore: The previous evaluation score.
    /// - Returns: True if rollback was triggered.
    @discardableResult
    public func rollbackIfWorse(newScore: Double, previousScore: Double) -> Bool {
        let degradation = (previousScore - newScore) / previousScore

        if degradation > degradationThreshold {
            _ = rollbackToPrevious()
            return true
        }

        return false
    }

    // MARK: - Analysis

    /// Gets the best performing version.
    public var bestVersion: PromptVersion? {
        storage.withLock { storage in
            storage.versions.max { $0.evaluationScore < $1.evaluationScore }
        }
    }

    /// Gets the score trend over recent versions.
    ///
    /// - Parameter count: Number of recent versions to analyze.
    /// - Returns: Average score change per version.
    public func scoreTrend(lastVersions count: Int = 5) -> Double {
        storage.withLock { storage in
            let recentVersions = Array(storage.versions.suffix(count))

            guard recentVersions.count >= 2 else {
                return 0
            }

            var totalChange = 0.0
            for i in 1..<recentVersions.count {
                totalChange += recentVersions[i].evaluationScore - recentVersions[i - 1].evaluationScore
            }

            return totalChange / Double(recentVersions.count - 1)
        }
    }
}

// MARK: - Internal Storage

private struct VersionStorage: Sendable {
    var versions: [PromptVersion] = []
    var nextVersion: Int = 1
}
