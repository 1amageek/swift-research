import SwiftUI
import SwiftResearch

public struct ContentView: View {
    @State private var viewModel = ResearchViewModel()
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            DetailView(viewModel: viewModel)
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Bindable var viewModel: ResearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Input Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Research Objective")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $viewModel.objective)
                    .font(.body)
                    .frame(minHeight: 100, maxHeight: 150)
                    .scrollContentBackground(.hidden)
                    .background(Color(.textBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .disabled(viewModel.isResearching)

                // Settings
                HStack {
                    Text("Max URLs:")
                        .foregroundStyle(.secondary)
                    Stepper(
                        value: $viewModel.maxURLs,
                        in: 10...200,
                        step: 10
                    ) {
                        Text("\(viewModel.maxURLs)")
                            .monospacedDigit()
                    }
                    .disabled(viewModel.isResearching)
                }

                // Action Button
                Button(action: {
                    Task {
                        await viewModel.startResearch()
                    }
                }) {
                    HStack {
                        if viewModel.isResearching {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(viewModel.isResearching ? "Researching..." : "Start Research")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.objective.isEmpty || viewModel.isResearching)
                .controlSize(.large)
            }
            .padding()

            Divider()

            // Keywords section when researching
            if viewModel.isResearching && !viewModel.keywords.isEmpty {
                KeywordsSidebarSection(
                    keywords: viewModel.keywords,
                    currentKeyword: viewModel.currentKeyword
                )
            }

            Spacer()

            // Stats Footer
            if viewModel.result != nil || viewModel.isResearching {
                StatsFooter(viewModel: viewModel)
            }
        }
        .navigationTitle("Research")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        #endif
    }
}

// MARK: - Keywords Sidebar Section

struct KeywordsSidebarSection: View {
    let keywords: [String]
    let currentKeyword: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keywords")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(keywords, id: \.self) { keyword in
                        KeywordBadge(
                            keyword: keyword,
                            isActive: keyword == currentKeyword
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
        .background(Color(.controlBackgroundColor).opacity(0.3))
    }
}

struct KeywordBadge: View {
    let keyword: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isActive {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            }
            Text(keyword)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isActive ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
        .foregroundStyle(isActive ? .blue : .secondary)
        .clipShape(Capsule())
    }
}

// MARK: - Stats Footer

struct StatsFooter: View {
    let viewModel: ResearchViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 24) {
                StatItem(
                    icon: "doc.text",
                    value: "\(viewModel.visitedURLs)",
                    label: "Visited",
                    color: .blue
                )
                StatItem(
                    icon: "checkmark.circle",
                    value: "\(viewModel.relevantPages)",
                    label: "Relevant",
                    color: .green
                )
                if viewModel.isResearching {
                    StatItem(
                        icon: "arrow.trianglehead.2.clockwise",
                        value: "\(viewModel.processingURLs.count)",
                        label: "Active",
                        color: .orange
                    )
                } else if let result = viewModel.result {
                    StatItem(
                        icon: "key",
                        value: "\(result.keywordsUsed.count)",
                        label: "Keywords",
                        color: .purple
                    )
                }
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    let viewModel: ResearchViewModel

    var body: some View {
        Group {
            if let result = viewModel.result {
                ResultView(
                    result: result,
                    sentPrompts: viewModel.sentPrompts,
                    activityLog: viewModel.activityLog,
                    explorationItems: viewModel.explorationItems
                )
            } else if let error = viewModel.error {
                ErrorView(error: error, onRetry: {
                    Task {
                        await viewModel.startResearch()
                    }
                })
            } else if viewModel.isResearching {
                ExplorationView(viewModel: viewModel)
            } else {
                EmptyStateView()
            }
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Start Your Research", systemImage: "magnifyingglass.circle")
        } description: {
            Text("Enter a research objective in the sidebar and click \"Start Research\" to begin.")
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: String
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Research Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Phase Indicator

struct PhaseIndicator: View {
    let phase: ResearchViewModel.ResearchPhase

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: phase.icon)
                .foregroundStyle(phase.color)
            Text(phase.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
