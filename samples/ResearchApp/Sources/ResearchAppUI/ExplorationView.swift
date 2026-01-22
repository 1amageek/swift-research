import SwiftUI
import SwiftResearch

/// View showing real-time URL exploration progress
public struct ExplorationView: View {
    let viewModel: ResearchViewModel
    @State private var selectedTab: ExplorationTab = .activity
    @State private var selectedActivityItem: ResearchViewModel.ActivityLogItem?
    @State private var selectedExplorationItem: ResearchViewModel.ExplorationItem?
    @State private var showInspector: Bool = false

    enum ExplorationTab: String, CaseIterable {
        case activity = "Activity"
        case urls = "URLs"

        var icon: String {
            switch self {
            case .activity: return "list.bullet.rectangle"
            case .urls: return "link"
            }
        }
    }

    public init(viewModel: ResearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with current phase and stats
            ExplorationHeader(viewModel: viewModel)

            Divider()

            // Tab selector
            Picker("View", selection: $selectedTab) {
                ForEach(ExplorationTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content based on selected tab
            switch selectedTab {
            case .activity:
                ActivityTimelineView(
                    activityLog: viewModel.activityLog,
                    selectedItem: $selectedActivityItem
                )
            case .urls:
                URLExplorationView(
                    items: viewModel.explorationItems,
                    keywords: viewModel.keywords,
                    currentKeyword: viewModel.currentKeyword,
                    selectedItem: $selectedExplorationItem
                )
            }
        }
        .inspector(isPresented: $showInspector) {
            ExplorationInspectorView(
                activityItem: selectedActivityItem,
                explorationItem: selectedExplorationItem
            )
            .inspectorColumnWidth(min: 300, ideal: 350, max: 450)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Toggle Inspector")
            }
        }
        .onChange(of: selectedActivityItem) { _, newValue in
            if newValue != nil {
                selectedExplorationItem = nil
                showInspector = true
            }
        }
        .onChange(of: selectedExplorationItem) { _, newValue in
            if newValue != nil {
                selectedActivityItem = nil
                showInspector = true
            }
        }
    }
}

// MARK: - Exploration Inspector View

struct ExplorationInspectorView: View {
    let activityItem: ResearchViewModel.ActivityLogItem?
    let explorationItem: ResearchViewModel.ExplorationItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let item = activityItem {
                    ActivityItemDetail(item: item)
                } else if let item = explorationItem {
                    ExplorationItemDetail(item: item)
                } else {
                    ContentUnavailableView {
                        Label("No Selection", systemImage: "sidebar.right")
                    } description: {
                        Text("Select an activity or URL to view details")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Details")
    }
}

// MARK: - Activity Timeline View

struct ActivityTimelineView: View {
    let activityLog: [ResearchViewModel.ActivityLogItem]
    @Binding var selectedItem: ResearchViewModel.ActivityLogItem?

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }

    var body: some View {
        if activityLog.isEmpty {
            ContentUnavailableView {
                Label("No Activity Yet", systemImage: "clock")
            } description: {
                Text("Activity will appear here as research progresses")
            }
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(activityLog) { item in
                        ActivityLogRow(
                            item: item,
                            isSelected: selectedItem?.id == item.id,
                            timeFormatter: timeFormatter
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedItem = item
                        }
                    }
                }
                .listStyle(.plain)
                .onChange(of: activityLog.count) { _, _ in
                    // Auto-scroll to latest item
                    if let lastItem = activityLog.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastItem.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

struct ActivityLogRow: View {
    let item: ResearchViewModel.ActivityLogItem
    let isSelected: Bool
    let timeFormatter: DateFormatter

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(item.type.color.opacity(0.15))
                    .frame(width: 28, height: 28)

                Image(systemName: item.type.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(item.type.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Message
                HStack {
                    Text(item.message)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text(timeFormatter.string(from: item.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                // Details
                if let details = item.details, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                // URL link
                if let url = item.url {
                    Button(action: { openURL(url) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                            Text(url.host ?? url.absoluteString)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private func openURL(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - URL Exploration View

struct URLExplorationView: View {
    let items: [ResearchViewModel.ExplorationItem]
    let keywords: [String]
    let currentKeyword: String?
    @Binding var selectedItem: ResearchViewModel.ExplorationItem?

    var body: some View {
        VStack(spacing: 0) {
            // Keywords section
            if !keywords.isEmpty {
                KeywordsSection(
                    keywords: keywords,
                    currentKeyword: currentKeyword
                )
                Divider()
            }

            // URL list
            if items.isEmpty {
                ContentUnavailableView {
                    Label("Waiting for URLs", systemImage: "magnifyingglass")
                } description: {
                    Text("URLs will appear here as they are discovered")
                }
            } else {
                ExplorationList(items: items, selectedItem: $selectedItem)
            }
        }
    }
}

// MARK: - Header

struct ExplorationHeader: View {
    let viewModel: ResearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Phase indicator
            HStack {
                Image(systemName: viewModel.currentPhase.icon)
                    .font(.title2)
                    .foregroundStyle(viewModel.currentPhase.color)
                    .symbolEffect(.pulse, isActive: viewModel.isResearching)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentPhase.rawValue)
                        .font(.headline)

                    if let keyword = viewModel.currentKeyword {
                        Text("Searching: \(keyword)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Live stats
                HStack(spacing: 16) {
                    LiveStatBadge(
                        icon: "doc.text",
                        value: viewModel.visitedURLs,
                        label: "Visited",
                        color: .blue
                    )
                    LiveStatBadge(
                        icon: "checkmark.circle",
                        value: viewModel.relevantPages,
                        label: "Relevant",
                        color: .green
                    )
                    LiveStatBadge(
                        icon: "arrow.trianglehead.2.clockwise",
                        value: viewModel.processingURLs.count,
                        label: "Active",
                        color: .orange
                    )
                }
            }

            // Progress bar
            if viewModel.isResearching {
                ProgressView(value: Double(viewModel.visitedURLs), total: Double(viewModel.maxURLs))
                    .tint(viewModel.currentPhase.color)

                Text("\(viewModel.visitedURLs) / \(viewModel.maxURLs) URLs processed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }
}

struct LiveStatBadge: View {
    let icon: String
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text("\(value)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(color)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Keywords Section

struct KeywordsSection: View {
    let keywords: [String]
    let currentKeyword: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search Keywords")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(keywords, id: \.self) { keyword in
                    KeywordChip(
                        keyword: keyword,
                        isActive: keyword == currentKeyword
                    )
                }
            }
        }
        .padding()
    }
}

struct KeywordChip: View {
    let keyword: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isActive {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            }
            Text(keyword)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
        .foregroundStyle(isActive ? .blue : .secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(isActive ? Color.blue : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Exploration List

struct ExplorationList: View {
    let items: [ResearchViewModel.ExplorationItem]
    @Binding var selectedItem: ResearchViewModel.ExplorationItem?

    var body: some View {
        List {
            // Processing items first
            let processingItems = items.filter { $0.status == .processing }
            let completedItems = items.filter { $0.status != .processing && $0.status != .queued }
            let queuedItems = items.filter { $0.status == .queued }

            if !processingItems.isEmpty {
                Section("Processing") {
                    ForEach(processingItems) { item in
                        ExplorationItemRow(item: item, isSelected: selectedItem?.id == item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                }
            }

            if !completedItems.isEmpty {
                Section("Completed (\(completedItems.count))") {
                    ForEach(completedItems.reversed()) { item in
                        ExplorationItemRow(item: item, isSelected: selectedItem?.id == item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                }
            }

            if !queuedItems.isEmpty {
                Section("Queued (\(queuedItems.count))") {
                    ForEach(queuedItems.prefix(10)) { item in
                        ExplorationItemRow(item: item, isSelected: selectedItem?.id == item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                    if queuedItems.count > 10 {
                        Text("+ \(queuedItems.count - 10) more in queue")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct ExplorationItemRow: View {
    let item: ResearchViewModel.ExplorationItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(item.status.color.opacity(0.15))
                    .frame(width: 32, height: 32)

                if item.status == .processing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: item.status.icon)
                        .font(.system(size: 14))
                        .foregroundStyle(item.status.color)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                // Title or host
                Text(item.title ?? item.url.host ?? item.url.absoluteString)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // URL
                Text(item.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                // Extracted info
                if let info = item.extractedInfo, !info.isEmpty {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                // Metadata row
                HStack(spacing: 12) {
                    if let isRelevant = item.isRelevant {
                        Label(
                            isRelevant ? "Relevant" : "Not Relevant",
                            systemImage: isRelevant ? "checkmark.circle.fill" : "minus.circle"
                        )
                        .font(.caption2)
                        .foregroundStyle(isRelevant ? .green : .secondary)
                    }

                    if let duration = item.duration {
                        Label(
                            String(format: "%.1fs", duration),
                            systemImage: "clock"
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}

#Preview {
    let viewModel = ResearchViewModel()
    ExplorationView(viewModel: viewModel)
}
