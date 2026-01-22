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

    // Activity log for real-time tracking
    public var activityLog: [ActivityLogItem] = []

    // Keyword to URL tracking (for associating URLs with their discovery keyword)
    private var keywordURLMapping: [URL: String] = [:]

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

    /// Represents an activity log entry
    public struct ActivityLogItem: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let timestamp: Date
        public let type: ActivityType
        public let message: String
        public let details: String?          // Truncated for list display
        public let fullDetails: String?      // Full content for Inspector
        public let url: URL?
        public let relatedPromptId: UUID?    // Reference to related prompt

        public init(
            type: ActivityType,
            message: String,
            details: String? = nil,
            fullDetails: String? = nil,
            url: URL? = nil,
            relatedPromptId: UUID? = nil
        ) {
            self.id = UUID()
            self.timestamp = Date()
            self.type = type
            self.message = message
            self.details = details
            self.fullDetails = fullDetails
            self.url = url
            self.relatedPromptId = relatedPromptId
        }

        public static func == (lhs: ActivityLogItem, rhs: ActivityLogItem) -> Bool {
            lhs.id == rhs.id
        }
    }

    public enum ActivityType: String, Sendable {
        case phaseStart = "Phase Start"
        case search = "Search"
        case urlFound = "URL Found"
        case urlProcessing = "Processing"
        case urlSuccess = "Success"
        case urlFailed = "Failed"
        case sufficiency = "Sufficiency"
        case prompt = "LLM Prompt"
        case info = "Info"
        case error = "Error"

        public var icon: String {
            switch self {
            case .phaseStart: return "flag.fill"
            case .search: return "magnifyingglass"
            case .urlFound: return "link"
            case .urlProcessing: return "arrow.triangle.2.circlepath"
            case .urlSuccess: return "checkmark.circle.fill"
            case .urlFailed: return "xmark.circle.fill"
            case .sufficiency: return "checkmark.seal"
            case .prompt: return "text.bubble"
            case .info: return "info.circle"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        public var color: Color {
            switch self {
            case .phaseStart: return .purple
            case .search: return .blue
            case .urlFound: return .cyan
            case .urlProcessing: return .orange
            case .urlSuccess: return .green
            case .urlFailed: return .red
            case .sufficiency: return .teal
            case .prompt: return .indigo
            case .info: return .secondary
            case .error: return .red
            }
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
    public struct ExplorationItem: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let url: URL
        public let timestamp: Date
        public var title: String?
        public var extractedInfo: String?
        public var isRelevant: Bool?
        public var status: ExplorationStatus
        public var duration: TimeInterval?

        // Additional fields for detailed view
        public var keyword: String?              // Keyword that discovered this URL
        public var rawMarkdown: String?          // Raw markdown from Remark
        public var relevantRanges: [Range<Int>]? // Relevant line ranges
        public var excerpts: [String]?           // Extracted text from relevant ranges

        public init(url: URL) {
            self.id = UUID()
            self.url = url
            self.timestamp = Date()
            self.status = .processing
        }

        public static func == (lhs: ExplorationItem, rhs: ExplorationItem) -> Bool {
            lhs.id == rhs.id
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
        activityLog = []
        keywordURLMapping = [:]
        currentPhase = .analyzing

        // Log start
        activityLog.append(ActivityLogItem(
            type: .info,
            message: "Research started",
            details: "Objective: \(objective)"
        ))

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
                    #if USE_OTHER_MODELS
                    let model = ResearchViewModel.createModel()
                    #else
                    let model = SystemLanguageModel()
                    #endif
                    return LanguageModelSession(model: model, tools: [], instructions: ResearchViewModel.systemInstructions())
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

            // Populate excerpts and relevantRanges from reviewedContents
            populateReviewedContentData(from: aggregatedResult.reviewedContents)

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
            let phaseName: String
            switch phase {
            case .initialSearch:
                currentPhase = .initialSearch
                phaseName = "Initial Search"
            case .analyzing:
                currentPhase = .analyzing
                phaseName = "Objective Analysis"
            case .searching:
                currentPhase = .searching
                phaseName = "Searching"
            case .reviewing:
                currentPhase = .reviewing
                phaseName = "Content Review"
            case .checkingSufficiency:
                currentPhase = .checkingSufficiency
                phaseName = "Sufficiency Check"
            case .buildingResponse:
                currentPhase = .buildingResponse
                phaseName = "Response Building"
            case .completed:
                currentPhase = .completed
                phaseName = "Completed"
            }
            activityLog.append(ActivityLogItem(
                type: .phaseStart,
                message: "Phase: \(phaseName)",
                details: nil
            ))

        case .keywordsGenerated(let newKeywords):
            keywords = newKeywords
            activityLog.append(ActivityLogItem(
                type: .info,
                message: "Keywords generated",
                details: newKeywords.joined(separator: ", ")
            ))

        case .searchStarted(let keyword):
            currentKeyword = keyword
            activityLog.append(ActivityLogItem(
                type: .search,
                message: "Searching: \(keyword)",
                details: nil
            ))

        case .urlsFound(let keyword, let urls):
            // Track keyword → URL mapping and add URLs as queued items
            for url in urls {
                keywordURLMapping[url] = keyword
                if !explorationItems.contains(where: { $0.url == url }) {
                    var item = ExplorationItem(url: url)
                    item.status = .queued
                    item.keyword = keyword
                    explorationItems.append(item)
                }
            }
            let fullURLList = urls.map { $0.absoluteString }.joined(separator: "\n")
            activityLog.append(ActivityLogItem(
                type: .urlFound,
                message: "Found \(urls.count) URLs for '\(keyword)'",
                details: urls.prefix(3).map { $0.host ?? $0.absoluteString }.joined(separator: ", ") + (urls.count > 3 ? "..." : ""),
                fullDetails: fullURLList
            ))

        case .urlProcessingStarted(let url):
            processingURLs.insert(url)
            if let index = explorationItems.firstIndex(where: { $0.url == url }) {
                explorationItems[index].status = .processing
                // Set keyword if not already set
                if explorationItems[index].keyword == nil {
                    explorationItems[index].keyword = keywordURLMapping[url]
                }
            } else {
                var item = ExplorationItem(url: url)
                item.status = .processing
                item.keyword = keywordURLMapping[url]
                explorationItems.append(item)
            }
            activityLog.append(ActivityLogItem(
                type: .urlProcessing,
                message: "Processing: \(url.host ?? url.absoluteString)",
                details: nil,
                url: url
            ))

        case .contentFetched(let url, let markdown, let title):
            // Store raw markdown content for the URL
            if let index = explorationItems.firstIndex(where: { $0.url == url }) {
                explorationItems[index].rawMarkdown = markdown
                if let title = title {
                    explorationItems[index].title = title
                }
            }
            // Log content fetch (truncated for list, full for inspector)
            let previewLines = markdown.split(separator: "\n").prefix(5).joined(separator: "\n")
            activityLog.append(ActivityLogItem(
                type: .info,
                message: "Content fetched: \(title ?? url.host ?? "Unknown")",
                details: String(previewLines.prefix(150)) + (previewLines.count > 150 ? "..." : ""),
                fullDetails: markdown,
                url: url
            ))

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

            let statusType: ActivityType = result.status == .success ? .urlSuccess : .urlFailed
            let relevanceText = result.isRelevant ? " [Relevant]" : ""
            let infoPreview = result.extractedInfo.prefix(100)
            activityLog.append(ActivityLogItem(
                type: statusType,
                message: "\(result.title ?? result.url.host ?? "Unknown")\(relevanceText)",
                details: infoPreview.isEmpty ? nil : String(infoPreview) + (result.extractedInfo.count > 100 ? "..." : ""),
                fullDetails: result.extractedInfo,
                url: result.url
            ))

        case .sufficiencyChecked(let isSufficient, let reason):
            let statusText = isSufficient ? "Sufficient" : "Not sufficient"
            activityLog.append(ActivityLogItem(
                type: .sufficiency,
                message: "Sufficiency: \(statusText)",
                details: String(reason.prefix(200)) + (reason.count > 200 ? "..." : ""),
                fullDetails: reason
            ))

        case .additionalKeywords(let newKeywords):
            keywords.append(contentsOf: newKeywords)
            activityLog.append(ActivityLogItem(
                type: .info,
                message: "Additional keywords",
                details: newKeywords.joined(separator: ", ")
            ))

        case .buildingResponse:
            currentPhase = .buildingResponse

        case .promptSent(let phase, let prompt):
            let sentPrompt = SentPrompt(phase: phase, prompt: prompt)
            sentPrompts.append(sentPrompt)
            activityLog.append(ActivityLogItem(
                type: .prompt,
                message: "LLM Prompt: \(phase)",
                details: String(prompt.prefix(150)) + (prompt.count > 150 ? "..." : ""),
                fullDetails: prompt,
                relatedPromptId: sentPrompt.id
            ))

        case .completed(let statistics):
            visitedURLs = statistics.totalPagesVisited
            relevantPages = statistics.relevantPagesFound
            activityLog.append(ActivityLogItem(
                type: .info,
                message: "Research completed",
                details: "Visited: \(statistics.totalPagesVisited), Relevant: \(statistics.relevantPagesFound)"
            ))

        case .error(let message):
            self.error = message
            activityLog.append(ActivityLogItem(
                type: .error,
                message: "Error occurred",
                details: message
            ))
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
        activityLog = []
        keywordURLMapping = [:]
    }

    // MARK: - Private

    /// Populates excerpts and relevantRanges from ReviewedContent into ExplorationItems
    private func populateReviewedContentData(from reviewedContents: [ReviewedContent]) {
        for content in reviewedContents {
            if let index = explorationItems.firstIndex(where: { $0.url == content.url }) {
                explorationItems[index].excerpts = content.excerpts
                explorationItems[index].relevantRanges = content.relevantRanges
                // Update extractedInfo if not already set or empty
                if explorationItems[index].extractedInfo?.isEmpty ?? true {
                    explorationItems[index].extractedInfo = content.extractedInfo
                }
            }
        }
    }

    /// System instructions for JSON output to ensure proper array handling
    nonisolated private static func systemInstructions() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        let currentDateTime = formatter.string(from: Date())
        let timeZone = TimeZone.current.identifier

        return """
        あなたは情報収集エージェントです。ユーザーの質問に根拠を持って回答するための情報を収集・分析します。

        # 現在の日時
        \(currentDateTime) (\(timeZone))
        IMPORTANT: 「現在」「最新」などの時間表現はこの日時を基準に解釈すること

        # 出力規則
        - 常に有効なJSONオブジェクトで応答する（'{'で開始）
        - 配列フィールドはJSON配列として出力（例: "items": ["a", "b"]）
        - 文字列として配列を出力しない（例: "items": "a, b" は不可）
        - Markdownコードフェンスは含めない
        IMPORTANT: メタ的な説明（「JSONで提供しました」「以下が回答です」等）は出力しない

        # 行動規則
        - 事実に基づいて回答する
        - 不明な場合は推測せず、その旨を明記する
        - 質問の背景・理由・含意も考慮する

        # 分析の観点
        情報を収集・分析する際は以下の観点を考慮:
        - 事実: 具体的なデータ（数値、日付、名称）
        - 背景: その事実の理由や原因
        - 含意: それが意味すること、導かれる結論
        """
    }

    #if USE_OTHER_MODELS
    nonisolated private static func createModel() -> OllamaLanguageModel {
        let baseURL = URL(string: "http://127.0.0.1:11434")!
        let modelName = "lfm2.5-thinking"
        let config = OllamaConfiguration(baseURL: baseURL, timeout: 300)
        return OllamaLanguageModel(configuration: config, modelName: modelName)
    }

    private func createSession() -> LanguageModelSession {
        let model = Self.createModel()
        return LanguageModelSession(model: model, tools: [], instructions: Self.systemInstructions())
    }
    #else
    private func createSession() -> LanguageModelSession {
        let model = SystemLanguageModel()
        return LanguageModelSession(model: model, tools: [], instructions: Self.systemInstructions())
    }
    #endif
}
