import SwiftUI
import SwiftResearch
import Foundation

#if USE_OTHER_MODELS
import OpenFoundationModelsOllama
#endif

/// ViewModel for managing research state and operations
@MainActor
@Observable
public final class ResearchViewModel {

    // MARK: - State

    public var objective: String = ""
    public var maxURLs: Int = 50
    public var isResearching: Bool = false
    public var result: ResearchAgent.Result?
    public var error: String?
    public var currentPhase: ResearchPhase = .idle
    public var visitedURLs: Int = 0

    // MARK: - Types

    public enum ResearchPhase: String, CaseIterable, Sendable {
        case idle = "Idle"
        case researching = "Researching"
        case completed = "Completed"
        case failed = "Failed"

        public var icon: String {
            switch self {
            case .idle: return "circle"
            case .researching: return "magnifyingglass"
            case .completed: return "checkmark.seal.fill"
            case .failed: return "xmark.circle.fill"
            }
        }

        public var color: Color {
            switch self {
            case .idle: return .secondary
            case .researching: return .blue
            case .completed: return .green
            case .failed: return .red
            }
        }
    }

    public init() {}

    // MARK: - Actions

    public func startResearch() async {
        guard !objective.isEmpty else {
            error = "Please enter a research objective"
            return
        }

        isResearching = true
        result = nil
        error = nil
        visitedURLs = 0
        currentPhase = .researching

        do {
            let model = Self.createModel()
            let configuration = ResearchAgent.Configuration(
                maxURLs: maxURLs,
                blockedDomains: [],
                verbose: false
            )
            let agent = ResearchAgent(
                model: model,
                configuration: configuration
            )

            let researchResult = try await agent.research(objective)

            result = researchResult
            visitedURLs = researchResult.visitedURLs.count
            currentPhase = .completed
        } catch {
            currentPhase = .failed
            self.error = error.localizedDescription
        }

        isResearching = false
    }

    public func reset() {
        objective = ""
        result = nil
        error = nil
        currentPhase = .idle
        visitedURLs = 0
    }

    // MARK: - Private

    #if USE_OTHER_MODELS
    nonisolated private static func createModel() -> OllamaLanguageModel {
        let baseURL = URL(string: "http://127.0.0.1:11434")!
        let modelName = "lfm2.5-thinking"
        let config = OllamaConfiguration(baseURL: baseURL, timeout: 300)
        return OllamaLanguageModel(configuration: config, modelName: modelName)
    }
    #else
    nonisolated private static func createModel() -> SystemLanguageModel {
        return SystemLanguageModel()
    }
    #endif
}
