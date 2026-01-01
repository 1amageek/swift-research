import Foundation
import SwiftAgent
import OpenFoundationModels
import OpenFoundationModelsOllama
import RemarkKit

/// グローバルなログファイルハンドル
nonisolated(unsafe) var globalLogFileHandle: FileHandle?

/// 出力を即時フラッシュするprint（ログファイルにも出力）
@inline(__always)
internal func printFlush(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let output = items.map { String(describing: $0) }.joined(separator: separator)
    print(output, terminator: terminator)
    fflush(stdout)

    // ログファイルにも書き込み
    if let handle = globalLogFileHandle {
        let logLine = output + terminator
        if let data = logLine.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }
}

/// 検索からクロール、結果統合までをオーケストレーションするStep
/// 5フェーズ: 目的分析 → 検索・取得 → コンテンツレビュー → 充足度チェック → 応答構築
public struct SearchOrchestratorStep: Step, Sendable {
    public typealias Input = SearchQuery
    public typealias Output = AggregatedResult

    private let configuration: CrawlerConfiguration
    private let verbose: Bool
    private let logFileURL: URL?

    /// 訪問済みURL管理（Phase 2, 3, DeepCrawlで共有）
    @Memory var visitedURLs: Set<URL> = []

    public init(configuration: CrawlerConfiguration = .default, verbose: Bool = false, logFileURL: URL? = nil) {
        self.configuration = configuration
        self.verbose = verbose
        self.logFileURL = logFileURL
    }

    public func run(_ input: SearchQuery) async throws -> AggregatedResult {
        let startTime = Date()

        // ログファイルハンドルを設定
        if let logURL = logFileURL {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            globalLogFileHandle = try? FileHandle(forWritingTo: logURL)
        }
        defer {
            try? globalLogFileHandle?.close()
            globalLogFileHandle = nil
        }

        // LLM設定
        let llmConfig = OllamaConfiguration(
            baseURL: configuration.baseURL,
            timeout: configuration.timeout,
            keepAlive: "10m"
        )
        let llm = OllamaLanguageModel(
            configuration: llmConfig,
            modelName: configuration.modelName
        )

        printFlush("═══════════════════════════════════════════")
        printFlush("🎯 Phase 0: INPUT")
        printFlush("═══════════════════════════════════════════")
        printFlush("objective: \(input.objective)")
        printFlush("maxVisitedURLs: \(input.maxVisitedURLs)")
        printFlush("")

        // ===== Phase 1: 目的分析 =====
        printFlush("═══════════════════════════════════════════")
        printFlush("📊 Phase 1: OBJECTIVE ANALYSIS")
        printFlush("═══════════════════════════════════════════")
        let phase1Start = Date()
        let analysis = await analyzeObjective(
            objective: input.objective,
            llm: llm
        )
        let phase1Duration = Date().timeIntervalSince(phase1Start)
        printFlush("⏱️ Phase 1 duration: \(String(format: "%.1f", phase1Duration))s")

        // 非verboseモードではサマリーのみ表示（verboseは関数内で詳細表示済み）
        if !verbose {
            printFlush("keywords: [\(analysis.keywords.joined(separator: ", "))]")
            printFlush("questions: [\(analysis.questions.joined(separator: ", "))]")
            printFlush("successCriteria: [\(analysis.successCriteria.joined(separator: ", "))]")
        }
        printFlush("")

        // ===== Phase 2-4 ループ =====
        var reviewedContents: [ReviewedContent] = []
        var usedKeywords: [String] = []
        var pendingKeywords: [String] = analysis.keywords
        var usedKeywordSet: Set<String> = []
        visitedURLs = []  // リセット（新しいクエリ開始時）
        var totalPagesVisited = 0
        var previousRelevantCount = 0  // 前回ラウンド終了時の関連ページ数

        while let keyword = pendingKeywords.first {
            pendingKeywords.removeFirst()

            // URL上限チェック
            if totalPagesVisited >= input.maxVisitedURLs {
                printFlush("⚠️ URL limit reached (\(input.maxVisitedURLs))")
                break
            }

            // 重複キーワードをスキップ
            let normalizedKeyword = keyword.lowercased().trimmingCharacters(in: .whitespaces)
            if usedKeywordSet.contains(normalizedKeyword) {
                continue
            }

            usedKeywordSet.insert(normalizedKeyword)
            usedKeywords.append(keyword)

            printFlush("═══════════════════════════════════════════")
            printFlush("🔍 Phase 2: SEARCH [\(keyword)]")
            printFlush("═══════════════════════════════════════════")
            let phase2Start = Date()

            // ===== Phase 2: 検索・取得 =====
            let searchStep = SearchStep(
                searchEngine: configuration.searchEngine,
                blockedDomains: configuration.blockedDomains
            )

            let urls: [URL]
            do {
                urls = try await searchStep.run(KeywordSearchInput(keyword: keyword))
            } catch {
                printFlush("⚠️ Search failed for '\(keyword)': \(error)")
                continue
            }

            let phase2Duration = Date().timeIntervalSince(phase2Start)
            if verbose {
                printFlush("⏱️ Phase 2 duration: \(String(format: "%.1f", phase2Duration))s")
            }

            printFlush("Found \(urls.count) URLs:")
            for (i, url) in urls.enumerated() {
                printFlush("  [\(i+1)] \(url.absoluteString)")
            }
            printFlush("")

            // 重複URL除去
            let newURLs = urls.filter { !visitedURLs.contains($0) }
            if newURLs.isEmpty {
                printFlush("   ⏭️ All URLs already visited")
                continue
            }

            $visitedURLs.formUnion(newURLs)

            // ===== Phase 3: コンテンツレビュー =====
            printFlush("")
            printFlush("═══════════════════════════════════════════")
            printFlush("📄 Phase 3: CONTENT REVIEW")
            printFlush("═══════════════════════════════════════════")
            let phase3Start = Date()

            for url in newURLs {
                if totalPagesVisited >= input.maxVisitedURLs {
                    break
                }

                printFlush("--- Reviewing: \(url.absoluteString)")
                let pageStart = Date()

                let reviewResult = await fetchAndReview(
                    url: url,
                    objective: input.objective,
                    llm: llm
                )

                let pageDuration = Date().timeIntervalSince(pageStart)
                totalPagesVisited += 1

                guard let result = reviewResult else {
                    if verbose {
                        printFlush("    ⏱️ \(String(format: "%.1f", pageDuration))s - FAILED")
                    } else {
                        printFlush("    fetch: FAILED")
                    }
                    continue
                }

                // 時間とサマリーを表示（詳細はreviewContent内で表示済み）
                printFlush("    ⏱️ total: \(String(format: "%.1f", result.totalDuration))s (fetch: \(String(format: "%.1f", result.fetchDuration))s, llm: \(String(format: "%.1f", result.llmDuration))s)")

                // 非verboseモードではサマリーのみ表示
                if !verbose {
                    printFlush("    isRelevant: \(result.reviewed.isRelevant)")
                    printFlush("    extractedInfo: \(result.reviewed.extractedInfo.prefix(100))...")
                    printFlush("    shouldDeepCrawl: \(result.shouldDeepCrawl)")
                }

                if result.reviewed.isRelevant {
                    reviewedContents.append(result.reviewed)

                    // 深掘り処理
                    if result.shouldDeepCrawl, let deepResults = result.deepCrawlResults {
                        if !verbose {
                            printFlush("    ┌─ Deep Crawl (\(deepResults.count) pages)")
                        }
                        for (idx, deepResult) in deepResults.enumerated() {
                            totalPagesVisited += 1
                            if !verbose {
                                let prefix = idx == deepResults.count - 1 ? "└" : "├"
                                printFlush("    \(prefix)─ [\(idx+1)] \(deepResult.reviewed.url.absoluteString)")
                                printFlush("    │     isRelevant: \(deepResult.reviewed.isRelevant)")
                                printFlush("    │     extractedInfo: \(deepResult.reviewed.extractedInfo.prefix(50))...")
                            }
                            if deepResult.reviewed.isRelevant {
                                reviewedContents.append(deepResult.reviewed)
                            }
                        }
                    }
                }

                // リクエスト間隔
                try? await Task.sleep(for: configuration.requestDelay)
            }

            let phase3Duration = Date().timeIntervalSince(phase3Start)
            printFlush("")
            printFlush("Phase 3 Summary: visited=\(totalPagesVisited), relevant=\(reviewedContents.count)")
            printFlush("⏱️ Phase 3 total: \(String(format: "%.1f", phase3Duration))s")
            printFlush("")

            // ===== Phase 4: 充足度チェック =====
            printFlush("═══════════════════════════════════════════")
            printFlush("✓ Phase 4: SUFFICIENCY CHECK")
            printFlush("═══════════════════════════════════════════")
            let phase4Start = Date()

            let newRelevantThisRound = reviewedContents.count - previousRelevantCount

            let sufficiency = await checkSufficiency(
                reviewedContents: reviewedContents,
                objective: input.objective,
                successCriteria: analysis.successCriteria,
                searchRoundNumber: usedKeywords.count,
                newRelevantThisRound: newRelevantThisRound,
                llm: llm
            )

            // 次ラウンドのために更新
            previousRelevantCount = reviewedContents.count

            let phase4Duration = Date().timeIntervalSince(phase4Start)
            printFlush("⏱️ Phase 4 duration: \(String(format: "%.1f", phase4Duration))s")

            // 非verboseモードではサマリーのみ表示（verboseは関数内で詳細表示済み）
            if !verbose {
                printFlush("isSufficient: \(sufficiency.isSufficient)")
                printFlush("shouldGiveUp: \(sufficiency.shouldGiveUp)")
                printFlush("additionalKeywords: [\(sufficiency.additionalKeywords.joined(separator: ", "))]")
                printFlush("reason: \(sufficiency.reasonMarkdown.prefix(150))...")
            }
            printFlush("")

            if sufficiency.isSufficient {
                printFlush("→ SUFFICIENT, exiting loop")
                break
            } else if sufficiency.shouldGiveUp {
                printFlush("→ GIVE UP, exiting loop")
                break
            } else {
                // 追加キーワードを追加
                let newKeywords = sufficiency.additionalKeywords.filter { keyword in
                    let normalized = keyword.lowercased().trimmingCharacters(in: .whitespaces)
                    return !usedKeywordSet.contains(normalized)
                }
                if !newKeywords.isEmpty {
                    printFlush("→ Adding \(newKeywords.count) new keywords")
                    pendingKeywords.append(contentsOf: newKeywords)
                }
            }
        }

        // ===== Phase 5: 応答構築 =====
        printFlush("═══════════════════════════════════════════")
        printFlush("📝 Phase 5: RESPONSE BUILDING")
        printFlush("═══════════════════════════════════════════")
        let phase5Start = Date()

        // 非verboseモードでは入力サマリーを表示（verboseは関数内で詳細表示）
        if !verbose {
            printFlush("input reviewedContents: \(reviewedContents.count) items")
            for (i, c) in reviewedContents.enumerated() {
                printFlush("  [\(i+1)] \(c.url.host ?? "?"): \(c.extractedInfo.prefix(60))...")
            }
            printFlush("")
        }

        let responseMarkdown = await buildFinalResponse(
            reviewedContents: reviewedContents,
            objective: input.objective,
            llm: llm
        )

        let phase5Duration = Date().timeIntervalSince(phase5Start)
        printFlush("⏱️ Phase 5 duration: \(String(format: "%.1f", phase5Duration))s")
        printFlush("output responseMarkdown: \(responseMarkdown.count) chars")
        printFlush("")

        let endTime = Date()

        let statistics = AggregatedStatistics(
            totalPagesVisited: totalPagesVisited,
            relevantPagesFound: reviewedContents.count,
            keywordsUsed: usedKeywords.count,
            duration: Duration.seconds(endTime.timeIntervalSince(startTime))
        )

        printFlush("")
        printFlush("🏁 Complete!")
        printFlush("   Visited: \(statistics.totalPagesVisited), Relevant: \(statistics.relevantPagesFound)")
        printFlush("   Keywords: \(statistics.keywordsUsed)")
        printFlush("   Duration: \(String(format: "%.1f", endTime.timeIntervalSince(startTime)))s")

        return AggregatedResult(
            objective: input.objective,
            questions: analysis.questions,
            successCriteria: analysis.successCriteria,
            reviewedContents: reviewedContents,
            responseMarkdown: responseMarkdown,
            keywordsUsed: usedKeywords,
            statistics: statistics
        )
    }

    // MARK: - Phase 1: Objective Analysis

    private func analyzeObjective(
        objective: String,
        llm: OllamaLanguageModel
    ) async -> ObjectiveAnalysis {
        // AMD Framework (arXiv:2502.08557) に基づくソクラテス的質問分解
        let prompt = """
        あなたは情報収集エージェントです。目的を分析してください。

        ## 目的
        \(objective)

        ## あなたの任務

        ### 1. 検索キーワード（keywords）
        目的を達成するための検索キーワードを3〜5個生成。
        - 英語で記述
        - 検索エンジン向け

        ### 2. 具体的な問い（questions）
        目的を達成するために答えるべき具体的な問いを3つ生成。
        - 明確化: 何を意味しているか？
        - 前提検証: 何を前提としているか？
        - 含意探索: 何が導かれるか？

        ### 3. 成功基準（successCriteria）
        情報収集が十分と判断する条件を2〜3個。
        - 具体的で検証可能な基準
        """

        // Verbose: プロンプトを表示
        if verbose {
            printFlush("┌─── LLM INPUT (ObjectiveAnalysis) ───")
            printFlush(prompt)
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        do {
            let session = LanguageModelSession(model: llm, tools: [], instructions: nil as String?)
            let response = try await session.respond(generating: ObjectiveAnalysisResponse.self) {
                Prompt(prompt)
            }

            // Verbose: 生のレスポンスを表示
            if verbose {
                printFlush("┌─── LLM OUTPUT (ObjectiveAnalysis) ───")
                printFlush("keywords: \(response.content.keywords)")
                printFlush("questions: \(response.content.questions)")
                printFlush("successCriteria: \(response.content.successCriteria)")
                printFlush("└─── END LLM OUTPUT ───")
                printFlush("")
            }

            // バリデーション: 異常な出力を検出
            let rawAnalysis = response.content

            // 1. 空チェック
            if rawAnalysis.keywords.isEmpty {
                printFlush("⚠️ LLM returned empty keywords, using fallback")
                return ObjectiveAnalysis.fallback(objective: objective)
            }

            // 2. 重複・過剰生成チェック（最大5個に制限、重複除去）
            let uniqueKeywords = Array(Set(rawAnalysis.keywords)).prefix(5)
            let uniqueQuestions = Array(Set(rawAnalysis.questions)).prefix(5)
            let uniqueCriteria = Array(Set(rawAnalysis.successCriteria)).prefix(3)

            // 3. 異常検出: 元の配列が10個以上なら警告
            if rawAnalysis.questions.count > 10 {
                printFlush("⚠️ LLM generated \(rawAnalysis.questions.count) questions (truncated to 5)")
            }

            return ObjectiveAnalysis(
                keywords: Array(uniqueKeywords),
                questions: Array(uniqueQuestions),
                successCriteria: Array(uniqueCriteria)
            )
        } catch {
            printFlush("⚠️ Objective analysis failed: \(error)")
            return ObjectiveAnalysis.fallback(objective: objective)
        }
    }

    // MARK: - Phase 3: Content Review

    /// Deep crawl結果（時間付き、続行判断付き）
    private struct DeepCrawlResult {
        let reviewed: ReviewedContent
        let shouldContinue: Bool
        let continueReason: String
        let fetchDuration: TimeInterval
        let llmDuration: TimeInterval
        var totalDuration: TimeInterval { fetchDuration + llmDuration }
    }

    /// フェッチとレビューの結果（時間付き）
    private struct FetchReviewResult {
        let reviewed: ReviewedContent
        let shouldDeepCrawl: Bool
        let deepCrawlResults: [DeepCrawlResult]?
        let priorityLinks: [PriorityLink]
        let fetchDuration: TimeInterval
        let llmDuration: TimeInterval
        var totalDuration: TimeInterval { fetchDuration + llmDuration }
    }

    private func fetchAndReview(
        url: URL,
        objective: String,
        llm: OllamaLanguageModel
    ) async -> FetchReviewResult? {
        // Remarkでフェッチ
        let fetchStart = Date()
        let remark: Remark
        let links: [Link]

        do {
            remark = try await withThrowingTaskGroup(of: Remark.self) { group in
                group.addTask {
                    try await Remark.fetch(from: url)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            links = try remark.extractLinks()
        } catch {
            printFlush("   ⚠️ Fetch failed: \(url.absoluteString)")
            printFlush("      Error: \(error)")
            return nil
        }
        let fetchDuration = Date().timeIntervalSince(fetchStart)

        // LLMでコンテンツから情報抽出（問い検証はPhase 4で実施）
        let llmStart = Date()
        let review = await reviewContent(
            markdown: remark.markdown,
            title: remark.title,
            links: links,
            sourceURL: url,
            objective: objective,
            llm: llm
        )
        let llmDuration = Date().timeIntervalSince(llmStart)

        let reviewed = ReviewedContent(
            url: url,
            title: remark.title.isEmpty ? nil : remark.title,
            extractedInfo: review.extractedInfo,
            isRelevant: review.isRelevant
        )

        // 深掘り処理
        var deepCrawlResults: [DeepCrawlResult]? = nil
        if review.shouldDeepCrawl && !review.priorityLinks.isEmpty {
            deepCrawlResults = await deepCrawlLinks(
                priorityLinks: review.priorityLinks,
                links: links,
                sourceURL: url,
                objective: objective,
                llm: llm
            )
        }

        return FetchReviewResult(
            reviewed: reviewed,
            shouldDeepCrawl: review.shouldDeepCrawl,
            deepCrawlResults: deepCrawlResults,
            priorityLinks: review.priorityLinks,
            fetchDuration: fetchDuration,
            llmDuration: llmDuration
        )
    }

    private func reviewContent(
        markdown: String,
        title: String,
        links: [Link],
        sourceURL: URL,
        objective: String,
        llm: OllamaLanguageModel,
        isDeepCrawl: Bool = false
    ) async -> ContentReview {
        let truncatedContent = String(markdown.prefix(2000))

        let linksInfo = links.prefix(5).enumerated().map { index, link in
            "[\(index + 1)] \(link.text.isEmpty ? "-" : String(link.text.prefix(30))) -> \(link.url)"
        }.joined(separator: "\n")

        let prompt = """
        目的に関連する情報を抽出してください。

        ## 目的
        \(objective)

        ## ページ: \(title)
        \(truncatedContent)

        ## リンク
        \(linksInfo)

        ## 出力（簡潔に）
        - isRelevant: 関連があるか
        - extractedInfo: 関連情報（100-200字）
        - shouldDeepCrawl: 深掘りすべきか
        - priorityLinks: 深掘り候補（最大2件）
        """

        let prefix = isDeepCrawl ? "    │     " : "    "

        // Verbose: プロンプトを表示
        if verbose {
            printFlush("\(prefix)┌─── LLM INPUT (ContentReview) ───")
            printFlush("\(prefix)objective: \(objective)")
            printFlush("\(prefix)title: \(title)")
            printFlush("\(prefix)content: \(truncatedContent.prefix(200))...")
            printFlush("\(prefix)links: \(links.count) items")
            printFlush("\(prefix)└─── END LLM INPUT ───")
        }

        do {
            let session = LanguageModelSession(model: llm, tools: [], instructions: nil as String?)
            let response = try await session.respond(generating: ContentReviewResponse.self) {
                Prompt(prompt)
            }

            // Verbose: 生のLLM出力を表示
            if verbose {
                printFlush("\(prefix)┌─── LLM OUTPUT (ContentReview) ───")
                printFlush("\(prefix)isRelevant: \(response.content.isRelevant)")
                printFlush("\(prefix)extractedInfo: \(response.content.extractedInfo)")
                printFlush("\(prefix)shouldDeepCrawl: \(response.content.shouldDeepCrawl)")
                printFlush("\(prefix)priorityLinks: \(response.content.priorityLinks)")
                printFlush("\(prefix)└─── END LLM OUTPUT ───")
            }

            return ContentReview(from: response.content)
        } catch {
            printFlush("   ⚠️ Review failed: \(error)")
            return ContentReview.irrelevant()
        }
    }

    /// 深掘りリンクをフェッチしてレビュー（履歴に基づく続行判断付き）
    private func deepCrawlLinks(
        priorityLinks: [PriorityLink],
        links: [Link],
        sourceURL: URL,
        objective: String,
        llm: OllamaLanguageModel
    ) async -> [DeepCrawlResult] {
        var results: [DeepCrawlResult] = []

        // スコア順にソート
        let sortedLinks = priorityLinks.sorted { $0.score > $1.score }

        for priorityLink in sortedLinks {
            guard priorityLink.index > 0 && priorityLink.index <= links.count else { continue }

            let link = links[priorityLink.index - 1]
            guard let resolvedURL = URL(string: link.url, relativeTo: sourceURL)?.absoluteURL else { continue }

            // ドメインチェック
            if !isAllowedDomain(resolvedURL) { continue }

            // 訪問済みチェック（@Memoryで管理）
            if visitedURLs.contains(resolvedURL) {
                if verbose {
                    printFlush("    │     ⏭️ Already visited: \(resolvedURL.absoluteString)")
                }
                continue
            }
            $visitedURLs.insert(resolvedURL)

            // フェッチとレビュー（履歴を渡す）
            if let result = await fetchAndReviewDeepCrawl(
                url: resolvedURL,
                objective: objective,
                previousResults: results,
                llm: llm
            ) {
                results.append(result)

                // LLMが「続けるべきでない」と判断したら中断
                if !result.shouldContinue {
                    if verbose {
                        printFlush("    ⏹️ DeepCrawl中断: \(result.continueReason)")
                    }
                    break
                }
            }

            try? await Task.sleep(for: configuration.requestDelay)
        }

        return results
    }

    /// 深掘り用フェッチ＆レビュー（履歴を考慮した続行判断付き）
    private func fetchAndReviewDeepCrawl(
        url: URL,
        objective: String,
        previousResults: [DeepCrawlResult],
        llm: OllamaLanguageModel
    ) async -> DeepCrawlResult? {
        let fetchStart = Date()
        let remark: Remark

        do {
            remark = try await withThrowingTaskGroup(of: Remark.self) { group in
                group.addTask {
                    try await Remark.fetch(from: url)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(15))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } catch {
            return nil
        }
        let fetchDuration = Date().timeIntervalSince(fetchStart)

        // 履歴情報を構築
        let historyInfo = previousResults.isEmpty ? "なし" : previousResults.enumerated().map { idx, result in
            "[\(idx + 1)] \(result.reviewed.url.host ?? "?"): \(result.reviewed.isRelevant ? "✓関連あり" : "✗関連なし") - \(result.reviewed.extractedInfo.prefix(50))..."
        }.joined(separator: "\n")

        let truncatedContent = String(remark.markdown.prefix(2000))

        let prompt = """
        あなたはリンク先ページをレビューするエージェントです。

        ## 目的
        \(objective)

        ## 現在のページ: \(remark.title)
        \(truncatedContent)

        ## これまでの履歴
        \(historyInfo)

        ## 出力
        - isRelevant: このページは目的に関連があるか
        - extractedInfo: 関連情報（100-200字、関連なしなら空文字）
        - shouldContinue: この親ページの他のリンク先も見るべきか
          重要: このページが関連なし(isRelevant=false)なら、shouldContinue=falseにすること
          （関連のないページからのリンク先も関連がない可能性が高い）
        - reason: 判断理由（1文で簡潔に）
        """

        let prefix = "    │     "

        if verbose {
            printFlush("\(prefix)┌─── LLM INPUT (DeepCrawlReview) ───")
            printFlush("\(prefix)objective: \(objective)")
            printFlush("\(prefix)title: \(remark.title)")
            printFlush("\(prefix)history: \(previousResults.count) items")
            printFlush("\(prefix)└─── END LLM INPUT ───")
        }

        let llmStart = Date()
        do {
            let session = LanguageModelSession(model: llm, tools: [], instructions: nil as String?)
            let response = try await session.respond(generating: DeepCrawlReviewResponse.self) {
                Prompt(prompt)
            }

            if verbose {
                printFlush("\(prefix)┌─── LLM OUTPUT (DeepCrawlReview) ───")
                printFlush("\(prefix)isRelevant: \(response.content.isRelevant)")
                printFlush("\(prefix)extractedInfo: \(response.content.extractedInfo)")
                printFlush("\(prefix)shouldContinue: \(response.content.shouldContinue)")
                printFlush("\(prefix)reason: \(response.content.reason)")
                printFlush("\(prefix)└─── END LLM OUTPUT ───")
            }

            let llmDuration = Date().timeIntervalSince(llmStart)

            let reviewed = ReviewedContent(
                url: url,
                title: remark.title.isEmpty ? nil : remark.title,
                extractedInfo: response.content.extractedInfo,
                isRelevant: response.content.isRelevant
            )

            return DeepCrawlResult(
                reviewed: reviewed,
                shouldContinue: response.content.shouldContinue,
                continueReason: response.content.reason,
                fetchDuration: fetchDuration,
                llmDuration: llmDuration
            )
        } catch {
            printFlush("\(prefix)⚠️ DeepCrawl review failed: \(error)")
            return nil
        }
    }

    // MARK: - Phase 4: Sufficiency Check

    private func checkSufficiency(
        reviewedContents: [ReviewedContent],
        objective: String,
        successCriteria: [String],
        searchRoundNumber: Int,
        newRelevantThisRound: Int,
        llm: OllamaLanguageModel
    ) async -> SufficiencyResult {
        guard !reviewedContents.isEmpty else {
            return SufficiencyResult.insufficient(reason: "まだ関連情報が収集できていません")
        }

        let collectedInfo = reviewedContents
            .prefix(10)
            .map { content in
                "【\(content.url.host ?? "unknown")】\(content.extractedInfo)"
            }
            .joined(separator: "\n")

        let criteriaList = successCriteria.enumerated()
            .map { "- \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        あなたは情報充足度を判断するエージェントです。

        ## 目的
        \(objective)

        ## 成功基準
        \(criteriaList)

        ## 検索履歴
        - 検索ラウンド: \(searchRoundNumber)回目
        - このラウンドで見つかった新規関連ページ: \(newRelevantThisRound)件
        - 累計関連ページ: \(reviewedContents.count)件

        ## これまでに収集した情報
        \(collectedInfo)

        ## 判断基準

        1. isSufficient: ユーザーが目的を達成できる状態か？
           - 一次情報源（公式サイト、ドキュメント等）が見つかった
           - 目的に対する概要や主要情報が把握できた

        2. shouldGiveUp: これ以上の情報収集は困難か？
           - このラウンドで新規関連ページが0件だった
           - 複数ラウンド経過しても情報が増えていない

        3. additionalKeywords: 本当に不足している場合のみ追加（最大2個）

        4. reasonMarkdown: 判断理由（簡潔に）
        """

        // Verbose: プロンプトを表示
        if verbose {
            printFlush("┌─── LLM INPUT (SufficiencyCheck) ───")
            printFlush("objective: \(objective)")
            printFlush("successCriteria: \(successCriteria)")
            printFlush("searchRound: \(searchRoundNumber), newRelevantThisRound: \(newRelevantThisRound)")
            printFlush("collectedInfo (\(reviewedContents.count) items):")
            for (i, c) in reviewedContents.prefix(5).enumerated() {
                printFlush("  [\(i+1)] \(c.url.host ?? "?"): \(c.extractedInfo.prefix(80))...")
            }
            if reviewedContents.count > 5 {
                printFlush("  ... and \(reviewedContents.count - 5) more")
            }
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        do {
            let session = LanguageModelSession(model: llm, tools: [], instructions: nil as String?)
            let response = try await session.respond(generating: SufficiencyCheckResponse.self) {
                Prompt(prompt)
            }

            // Verbose: 生のLLM出力を表示
            if verbose {
                printFlush("┌─── LLM OUTPUT (SufficiencyCheck) ───")
                printFlush("isSufficient: \(response.content.isSufficient)")
                printFlush("shouldGiveUp: \(response.content.shouldGiveUp)")
                printFlush("additionalKeywords: \(response.content.additionalKeywords)")
                printFlush("reasonMarkdown:")
                printFlush(response.content.reasonMarkdown)
                printFlush("└─── END LLM OUTPUT ───")
            }

            return SufficiencyResult(from: response.content)
        } catch {
            printFlush("⚠️ Sufficiency check failed: \(error)")
            return SufficiencyResult.insufficient(reason: "充足度チェック失敗")
        }
    }

    // MARK: - Phase 5: Response Building

    private func buildFinalResponse(
        reviewedContents: [ReviewedContent],
        objective: String,
        llm: OllamaLanguageModel
    ) async -> String {
        guard !reviewedContents.isEmpty else {
            return "# \(objective)\n\n関連情報を収集できませんでした。"
        }

        let collectedInfo = reviewedContents.enumerated().map { index, content in
            "[\(index + 1)] \(content.url.host ?? "unknown"): \(content.extractedInfo)"
        }.joined(separator: "\n")

        let prompt = """
        あなたはレポートを作成する専門家です。

        ## 目的
        \(objective)

        ## 収集した情報
        \(collectedInfo)

        ## あなたの任務

        収集した情報に基づいて、目的に対する包括的な回答をMarkdown形式で作成してください。

        - 具体的な情報とエビデンスを含める
        - 読みやすい構造で記述
        - ソースURLは後でシステムが追加するため、参照リストは含めない
        """

        // Verbose: プロンプトを表示
        if verbose {
            printFlush("┌─── LLM INPUT (FinalResponse) ───")
            printFlush("objective: \(objective)")
            printFlush("collectedInfo (\(reviewedContents.count) items):")
            for (i, c) in reviewedContents.enumerated() {
                printFlush("  [\(i+1)] \(c.url.host ?? "?"): \(c.extractedInfo.prefix(60))...")
            }
            printFlush("└─── END LLM INPUT ───")
            printFlush("")
        }

        do {
            let session = LanguageModelSession(model: llm, tools: [], instructions: nil as String?)
            let response = try await session.respond(generating: FinalResponseBuildingResponse.self) {
                Prompt(prompt)
            }

            // Verbose: 生のLLM出力を表示
            if verbose {
                printFlush("┌─── LLM OUTPUT (FinalResponse) ───")
                printFlush("responseMarkdown (\(response.content.responseMarkdown.count) chars):")
                printFlush(response.content.responseMarkdown)
                printFlush("└─── END LLM OUTPUT ───")
            }

            var responseMarkdown = response.content.responseMarkdown
            responseMarkdown += "\n\n## 参照ソース\n"
            for content in reviewedContents {
                responseMarkdown += "- \(content.url.absoluteString)\n"
            }

            return responseMarkdown
        } catch {
            printFlush("⚠️ Response building failed: \(error)")
            var fallback = "# \(objective)\n\n"
            fallback += collectedInfo
            fallback += "\n\n## 参照ソース\n"
            for content in reviewedContents {
                fallback += "- \(content.url.absoluteString)\n"
            }
            return fallback
        }
    }

    // MARK: - Domain Filtering

    private func isAllowedDomain(_ url: URL) -> Bool {
        guard let host = url.host else { return false }

        let builtInBlockedDomains = [
            "apps.apple.com", "play.google.com",
            "twitter.com", "x.com", "facebook.com", "linkedin.com", "instagram.com", "youtube.com",
            "amazon.com", "amazon.co.jp",
            "policy.medium.com", "help.medium.com",
            "support.google.com", "accounts.google.com", "about.google.com", "policies.google.com",
        ]

        if builtInBlockedDomains.contains(where: { host.contains($0) }) {
            return false
        }

        if configuration.blockedDomains.contains(where: { host.contains($0) }) {
            return false
        }

        let blockedPaths = [
            "/login", "/signin", "/sign_in", "/sign-in",
            "/signup", "/sign_up", "/sign-up", "/register",
            "/privacy", "/terms", "/tos",
            "/cart", "/checkout", "/buy",
            "/share", "/tweet",
        ]

        let path = url.path.lowercased()
        if blockedPaths.contains(where: { path.contains($0) }) {
            return false
        }

        if let allowed = configuration.allowedDomains {
            return allowed.contains(where: { host.contains($0) })
        }

        return true
    }
}
