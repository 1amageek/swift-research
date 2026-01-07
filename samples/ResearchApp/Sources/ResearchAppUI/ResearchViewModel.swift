import SwiftUI
import SwiftResearch
import Foundation

/// ViewModel for managing research state and operations
@MainActor
@Observable
public final class ResearchViewModel {

    // MARK: - State

    public var objective: String = ""
    public var maxURLs: Int = 50
    public var isResearching: Bool = false
    public var result: AggregatedResult?
    public var error: String?

    // Progress tracking
    public var currentPhase: ResearchPhase = .idle
    public var keywords: [String] = []
    public var currentKeyword: String?

    // URL exploration tracking
    public var explorationItems: [ExplorationItem] = []
    public var processingURLs: Set<URL> = []

    // Statistics
    public var visitedURLs: Int = 0
    public var relevantPages: Int = 0

    // Debug: LLM prompts
    public var sentPrompts: [SentPrompt] = []

    /// Represents a prompt sent to LLM for debugging
    public struct SentPrompt: Identifiable, Sendable {
        public let id: UUID
        public let phase: String
        public let prompt: String
        public let timestamp: Date

        public init(phase: String, prompt: String) {
            self.id = UUID()
            self.phase = phase
            self.prompt = prompt
            self.timestamp = Date()
        }
    }

    // MARK: - Types

    public enum ResearchPhase: String, CaseIterable, Sendable {
        case idle = "Idle"
        case initialSearch = "Initial Search"
        case analyzing = "Analyzing Objective"
        case searching = "Searching"
        case reviewing = "Reviewing Content"
        case checkingSufficiency = "Checking Sufficiency"
        case buildingResponse = "Building Response"
        case completed = "Completed"
        case failed = "Failed"

        public var icon: String {
            switch self {
            case .idle: return "circle"
            case .initialSearch: return "magnifyingglass.circle"
            case .analyzing: return "brain"
            case .searching: return "magnifyingglass"
            case .reviewing: return "doc.text.magnifyingglass"
            case .checkingSufficiency: return "checkmark.circle"
            case .buildingResponse: return "doc.text"
            case .completed: return "checkmark.seal.fill"
            case .failed: return "xmark.circle.fill"
            }
        }

        public var color: Color {
            switch self {
            case .idle: return .secondary
            case .initialSearch: return .indigo
            case .analyzing: return .purple
            case .searching: return .blue
            case .reviewing: return .orange
            case .checkingSufficiency: return .cyan
            case .buildingResponse: return .green
            case .completed: return .green
            case .failed: return .red
            }
        }
    }

    /// Represents a single URL exploration item
    public struct ExplorationItem: Identifiable, Sendable {
        public let id: UUID
        public let url: URL
        public let timestamp: Date
        public var title: String?
        public var extractedInfo: String?
        public var isRelevant: Bool?
        public var status: ExplorationStatus
        public var duration: TimeInterval?

        public init(url: URL) {
            self.id = UUID()
            self.url = url
            self.timestamp = Date()
            self.status = .processing
        }
    }

    public enum ExplorationStatus: String, Sendable {
        case queued = "Queued"
        case processing = "Processing"
        case success = "Success"
        case failed = "Failed"

        public var icon: String {
            switch self {
            case .queued: return "clock"
            case .processing: return "arrow.trianglehead.2.clockwise"
            case .success: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }

        public var color: Color {
            switch self {
            case .queued: return .secondary
            case .processing: return .blue
            case .success: return .green
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
        keywords = []
        currentKeyword = nil
        explorationItems = []
        processingURLs = []
        visitedURLs = 0
        relevantPages = 0
        sentPrompts = []
        currentPhase = .analyzing

        // Create progress stream
        let (stream, continuation) = AsyncStream<CrawlProgress>.makeStream()

        // Start progress monitoring task
        let monitorTask = Task { @MainActor in
            for await progress in stream {
                await self.handleProgress(progress)
            }
        }

        do {
            let session = createSession()

            // SystemLanguageModel does NOT support concurrent requests
            let researchConfig = ResearchConfiguration(llmSupportsConcurrency: false)
            let configuration = CrawlerConfiguration(researchConfiguration: researchConfig)

            // Provide session factory for non-concurrent LLM
            let orchestrator = SearchOrchestratorStep(
                session: session,
                sessionFactory: {
                    let model = SystemLanguageModel()
                    return LanguageModelSession(model: model, tools: [], instructions: nil as String?)
                },
                configuration: configuration,
                verbose: false,
                logFileURL: nil,
                progressContinuation: continuation
            )

            let query = SearchQuery(
                objective: objective,
                maxVisitedURLs: maxURLs
            )

            let aggregatedResult = try await orchestrator.run(query)

            continuation.finish()
            monitorTask.cancel()

            result = aggregatedResult
            currentPhase = .completed

        } catch {
            continuation.finish()
            monitorTask.cancel()

            currentPhase = .failed
            self.error = error.localizedDescription
        }

        isResearching = false
    }

    @MainActor
    private func handleProgress(_ progress: CrawlProgress) async {
        switch progress {
        case .started:
            break

        case .phaseChanged(let phase):
            switch phase {
            case .initialSearch:
                currentPhase = .initialSearch
            case .analyzing:
                currentPhase = .analyzing
            case .searching:
                currentPhase = .searching
            case .reviewing:
                currentPhase = .reviewing
            case .checkingSufficiency:
                currentPhase = .checkingSufficiency
            case .buildingResponse:
                currentPhase = .buildingResponse
            case .completed:
                currentPhase = .completed
            }

        case .keywordsGenerated(let newKeywords):
            keywords = newKeywords

        case .searchStarted(let keyword):
            currentKeyword = keyword

        case .urlsFound(_, let urls):
            // Add URLs as queued items
            for url in urls {
                if !explorationItems.contains(where: { $0.url == url }) {
                    var item = ExplorationItem(url: url)
                    item.status = .queued
                    explorationItems.append(item)
                }
            }

        case .urlProcessingStarted(let url):
            processingURLs.insert(url)
            if let index = explorationItems.firstIndex(where: { $0.url == url }) {
                explorationItems[index].status = .processing
            } else {
                var item = ExplorationItem(url: url)
                item.status = .processing
                explorationItems.append(item)
            }

        case .urlProcessed(let result):
            processingURLs.remove(result.url)
            visitedURLs += 1

            if result.isRelevant {
                relevantPages += 1
            }

            if let index = explorationItems.firstIndex(where: { $0.url == result.url }) {
                explorationItems[index].title = result.title
                explorationItems[index].extractedInfo = result.extractedInfo
                explorationItems[index].isRelevant = result.isRelevant
                explorationItems[index].duration = result.duration
                explorationItems[index].status = result.status == .success ? .success : .failed
            }

        case .sufficiencyChecked:
            break

        case .additionalKeywords(let newKeywords):
            keywords.append(contentsOf: newKeywords)

        case .buildingResponse:
            currentPhase = .buildingResponse

        case .promptSent(let phase, let prompt):
            sentPrompts.append(SentPrompt(phase: phase, prompt: prompt))

        case .completed(let statistics):
            visitedURLs = statistics.totalPagesVisited
            relevantPages = statistics.relevantPagesFound

        case .error(let message):
            self.error = message
        }
    }

    public func reset() {
        objective = ""
        result = nil
        error = nil
        currentPhase = .idle
        keywords = []
        currentKeyword = nil
        explorationItems = []
        processingURLs = []
        visitedURLs = 0
        relevantPages = 0
        sentPrompts = []
    }

    // MARK: - Private

    private func createSession() -> LanguageModelSession {
        let model = SystemLanguageModel()
        return LanguageModelSession(model: model, tools: [], instructions: nil as String?)
    }
}
