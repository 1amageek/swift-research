import SwiftUI
import SwiftResearch

struct ResultView: View {
    let result: AggregatedResult
    let sentPrompts: [ResearchViewModel.SentPrompt]
    let activityLog: [ResearchViewModel.ActivityLogItem]
    let explorationItems: [ResearchViewModel.ExplorationItem]
    @State private var selectedTab: ResultTab = .response
    @State private var selectedActivityItem: ResearchViewModel.ActivityLogItem?
    @State private var selectedExplorationItem: ResearchViewModel.ExplorationItem?
    @State private var showInspector: Bool = false

    enum ResultTab: String, CaseIterable {
        case response = "Response"
        case activity = "Activity"
        case sources = "Sources"
        case details = "Details"
        case debug = "Debug"

        var icon: String {
            switch self {
            case .response: return "doc.text"
            case .activity: return "list.bullet.rectangle"
            case .sources: return "link"
            case .details: return "info.circle"
            case .debug: return "ladybug"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ResultHeader(result: result)

            Divider()

            // Tab Picker
            Picker("Tab", selection: $selectedTab) {
                ForEach(ResultTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Content based on selected tab
            switch selectedTab {
            case .response:
                ResponseTab(result: result)
            case .activity:
                ActivityTab(
                    activityLog: activityLog,
                    explorationItems: explorationItems,
                    selectedActivityItem: $selectedActivityItem,
                    selectedExplorationItem: $selectedExplorationItem,
                    showInspector: $showInspector
                )
            case .sources:
                SourcesTab(result: result)
            case .details:
                DetailsTab(result: result)
            case .debug:
                DebugTab(sentPrompts: sentPrompts)
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(
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

// MARK: - Inspector View

struct InspectorView: View {
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
                        Text("Select an item to view details")
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Details")
    }
}

struct ActivityItemDetail: View {
    let item: ResearchViewModel.ActivityLogItem
    @State private var showFullDetails: Bool = false

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(item.type.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: item.type.icon)
                        .font(.title2)
                        .foregroundStyle(item.type.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.type.rawValue)
                        .font(.headline)
                    Text(timeFormatter.string(from: item.timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Message
            InspectorSection(title: "Message", icon: "text.bubble") {
                Text(item.message)
                    .font(.body)
            }

            // Details (truncated preview)
            if let details = item.details, !details.isEmpty {
                InspectorSection(title: "Details (Preview)", icon: "doc.text") {
                    Text(details)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            // Full Details (if available and different from preview)
            if let fullDetails = item.fullDetails, !fullDetails.isEmpty {
                InspectorSection(title: "Full Content", icon: "doc.plaintext") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(fullDetails.prefix(300)) + (fullDetails.count > 300 ? "..." : ""))
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)

                        if fullDetails.count > 300 {
                            Button {
                                showFullDetails = true
                            } label: {
                                Label("View Full Content (\(fullDetails.count) chars)", systemImage: "arrow.up.right.square")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            // URL
            if let url = item.url {
                InspectorSection(title: "Related URL", icon: "link") {
                    Link(destination: url) {
                        HStack {
                            Text(url.absoluteString)
                                .font(.caption)
                                .lineLimit(3)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
            }

            // Related Prompt ID
            if item.relatedPromptId != nil {
                InspectorSection(title: "Related Data", icon: "link.circle") {
                    Text("This activity has a related LLM prompt. Check the Debug tab for full prompt details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showFullDetails) {
            FullDetailsSheet(
                type: item.type.rawValue,
                timestamp: item.timestamp,
                content: item.fullDetails ?? ""
            )
        }
    }
}

// MARK: - Full Details Sheet

struct FullDetailsSheet: View {
    let type: String
    let timestamp: Date
    let content: String
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied: Bool = false

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(timeFormatter.string(from: timestamp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(content.count) chars")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor).opacity(0.5))

                Divider()

                // Content
                ScrollView {
                    Text(content)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .navigationTitle(type)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #else
        UIPasteboard.general.string = content
        #endif

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

struct ExplorationItemDetail: View {
    let item: ResearchViewModel.ExplorationItem
    @State private var showRawMarkdown: Bool = false

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(item.status.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: item.status.icon)
                        .font(.title2)
                        .foregroundStyle(item.status.color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title ?? item.url.host ?? "Unknown")
                        .font(.headline)
                        .lineLimit(2)
                    Text(item.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // URL
            InspectorSection(title: "URL", icon: "link") {
                Link(destination: item.url) {
                    HStack {
                        Text(item.url.absoluteString)
                            .font(.caption)
                            .lineLimit(3)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }

            // Basic Info
            InspectorSection(title: "Basic Info", icon: "info.circle") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Status")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: item.status.icon)
                                .foregroundStyle(item.status.color)
                            Text(item.status.rawValue)
                        }
                    }
                    if let isRelevant = item.isRelevant {
                        GridRow {
                            Text("Relevant")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Image(systemName: isRelevant ? "checkmark.circle.fill" : "minus.circle")
                                    .foregroundStyle(isRelevant ? .green : .secondary)
                                Text(isRelevant ? "Yes" : "No")
                            }
                        }
                    }
                    if let duration = item.duration {
                        GridRow {
                            Text("Duration")
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.2fs", duration))
                        }
                    }
                    if let keyword = item.keyword {
                        GridRow {
                            Text("Keyword")
                                .foregroundStyle(.secondary)
                            Text(keyword)
                                .foregroundStyle(.blue)
                        }
                    }
                    GridRow {
                        Text("Processed")
                            .foregroundStyle(.secondary)
                        Text(timeFormatter.string(from: item.timestamp))
                            .font(.caption)
                    }
                }
                .font(.caption)
            }

            // Extracted Info (LLM Summary)
            if let info = item.extractedInfo, !info.isEmpty {
                InspectorSection(title: "Extracted Information (LLM Summary)", icon: "doc.text") {
                    Text(info)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            // Excerpts (Relevant Text)
            if let excerpts = item.excerpts, !excerpts.isEmpty {
                InspectorSection(title: "Relevant Text (\(excerpts.count) excerpts)", icon: "text.quote") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(excerpts.enumerated()), id: \.offset) { index, excerpt in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Excerpt \(index + 1)")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.tertiary)
                                    if let ranges = item.relevantRanges, index < ranges.count {
                                        Text("(L\(ranges[index].lowerBound)-\(ranges[index].upperBound))")
                                            .font(.caption2)
                                            .fontDesign(.monospaced)
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                }
                                ScrollView {
                                    Text(excerpt)
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 100)
                            }
                            .padding(8)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }

            // Relevant Ranges (if excerpts not available but ranges are)
            if item.excerpts?.isEmpty ?? true, let ranges = item.relevantRanges, !ranges.isEmpty {
                InspectorSection(title: "Relevant Line Ranges", icon: "text.line.first.and.arrowtriangle.forward") {
                    Text(ranges.map { "L\($0.lowerBound)-\($0.upperBound)" }.joined(separator: ", "))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
            }

            // Raw Markdown
            if item.rawMarkdown != nil {
                InspectorSection(title: "Raw Content", icon: "doc.plaintext") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let markdown = item.rawMarkdown {
                            Text(String(markdown.prefix(200)) + (markdown.count > 200 ? "..." : ""))
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                        }
                        Button {
                            showRawMarkdown = true
                        } label: {
                            Label("View Full Content", systemImage: "arrow.up.right.square")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .sheet(isPresented: $showRawMarkdown) {
            RawMarkdownSheet(
                title: item.title ?? item.url.host ?? "Content",
                url: item.url,
                markdown: item.rawMarkdown ?? ""
            )
        }
    }
}

// MARK: - Inspector Section

struct InspectorSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            content
        }
    }
}

// MARK: - Raw Markdown Sheet

struct RawMarkdownSheet: View {
    let title: String
    let url: URL
    let markdown: String
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // URL header
                HStack {
                    Link(destination: url) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text(url.absoluteString)
                                .lineLimit(1)
                        }
                        .font(.caption)
                    }
                    Spacer()
                    Text("\(markdown.count) chars")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.controlBackgroundColor).opacity(0.5))

                Divider()

                // Content
                ScrollView {
                    Text(markdown)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label(isCopied ? "Copied!" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        #else
        UIPasteboard.general.string = markdown
        #endif

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Activity Tab

struct ActivityTab: View {
    let activityLog: [ResearchViewModel.ActivityLogItem]
    let explorationItems: [ResearchViewModel.ExplorationItem]
    @Binding var selectedActivityItem: ResearchViewModel.ActivityLogItem?
    @Binding var selectedExplorationItem: ResearchViewModel.ExplorationItem?
    @Binding var showInspector: Bool
    @State private var selectedSubTab: ActivitySubTab = .timeline

    enum ActivitySubTab: String, CaseIterable {
        case timeline = "Timeline"
        case urls = "URLs"

        var icon: String {
            switch self {
            case .timeline: return "clock"
            case .urls: return "link"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab picker
            Picker("View", selection: $selectedSubTab) {
                ForEach(ActivitySubTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            switch selectedSubTab {
            case .timeline:
                ActivityTimelineList(
                    activityLog: activityLog,
                    selectedItem: $selectedActivityItem
                )
            case .urls:
                ExplorationItemsList(
                    items: explorationItems,
                    selectedItem: $selectedExplorationItem
                )
            }
        }
    }
}

struct ActivityTimelineList: View {
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
                Label("No Activity", systemImage: "clock")
            } description: {
                Text("No activity was recorded during the research")
            }
        } else {
            List {
                ForEach(activityLog) { item in
                    ActivityTimelineRow(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        timeFormatter: timeFormatter
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct ActivityTimelineRow: View {
    let item: ResearchViewModel.ActivityLogItem
    let isSelected: Bool
    let timeFormatter: DateFormatter

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.type.color.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: item.type.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(item.type.color)
            }

            VStack(alignment: .leading, spacing: 4) {
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

                if let details = item.details, !details.isEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}

struct ExplorationItemsList: View {
    let items: [ResearchViewModel.ExplorationItem]
    @Binding var selectedItem: ResearchViewModel.ExplorationItem?

    private var completedItems: [ResearchViewModel.ExplorationItem] {
        items.filter { $0.status == .success || $0.status == .failed }
    }

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label("No URLs", systemImage: "link")
            } description: {
                Text("No URLs were explored during the research")
            }
        } else {
            List {
                ForEach(completedItems) { item in
                    SelectableExplorationRow(
                        item: item,
                        isSelected: selectedItem?.id == item.id
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedItem = item
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

struct SelectableExplorationRow: View {
    let item: ResearchViewModel.ExplorationItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.status.color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: item.status.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(item.status.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? item.url.host ?? item.url.absoluteString)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(item.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if let info = item.extractedInfo, !info.isEmpty {
                    Text(info)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

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

// MARK: - Header

struct ResultHeader: View {
    let result: AggregatedResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Research Results")
                .font(.title2)
                .fontWeight(.semibold)

            Text(result.objective)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 16) {
                Label("\(result.statistics.totalPagesVisited) pages", systemImage: "doc.text")
                Label("\(result.statistics.relevantPagesFound) relevant", systemImage: "checkmark.circle")
                Label(formatDuration(result.statistics.duration), systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private func formatDuration(_ duration: Duration) -> String {
        let seconds = duration.components.seconds
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

// MARK: - Response Tab

struct ResponseTab: View {
    let result: AggregatedResult
    @State private var isCopied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: copyToClipboard) {
                        Label(
                            isCopied ? "Copied!" : "Copy",
                            systemImage: isCopied ? "checkmark" : "doc.on.doc"
                        )
                    }
                    .buttonStyle(.bordered)
                }

                Text(result.responseMarkdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.responseMarkdown, forType: .string)
        #else
        UIPasteboard.general.string = result.responseMarkdown
        #endif

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

// MARK: - Sources Tab

struct SourcesTab: View {
    let result: AggregatedResult
    @State private var filter: SourceFilter = .all
    @State private var expandedItems: Set<URL> = []

    enum SourceFilter: String, CaseIterable {
        case all = "All"
        case relevant = "Relevant"
        case notRelevant = "Not Relevant"

        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .relevant: return "checkmark.circle.fill"
            case .notRelevant: return "minus.circle"
            }
        }
    }

    var filteredContents: [ReviewedContent] {
        switch filter {
        case .all:
            return result.reviewedContents
        case .relevant:
            return result.reviewedContents.filter { $0.isRelevant }
        case .notRelevant:
            return result.reviewedContents.filter { !$0.isRelevant }
        }
    }

    var relevantCount: Int {
        result.reviewedContents.filter { $0.isRelevant }.count
    }

    var notRelevantCount: Int {
        result.reviewedContents.filter { !$0.isRelevant }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(SourceFilter.allCases, id: \.self) { filterOption in
                        HStack {
                            Image(systemName: filterOption.icon)
                            Text(filterOption.rawValue)
                            switch filterOption {
                            case .all:
                                Text("(\(result.reviewedContents.count))")
                            case .relevant:
                                Text("(\(relevantCount))")
                            case .notRelevant:
                                Text("(\(notRelevantCount))")
                            }
                        }
                        .tag(filterOption)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()

                Button(action: {
                    if expandedItems.count == filteredContents.count {
                        expandedItems.removeAll()
                    } else {
                        expandedItems = Set(filteredContents.map { $0.url })
                    }
                }) {
                    Image(systemName: expandedItems.count == filteredContents.count ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                }
                .buttonStyle(.bordered)
                .help(expandedItems.count == filteredContents.count ? "Collapse All" : "Expand All")
            }
            .padding()

            Divider()

            // URL List
            if filteredContents.isEmpty {
                ContentUnavailableView {
                    Label("No URLs", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("No URLs match the current filter.")
                }
            } else {
                List {
                    ForEach(filteredContents, id: \.url) { content in
                        SourceDetailRow(
                            content: content,
                            isExpanded: expandedItems.contains(content.url),
                            onToggle: {
                                if expandedItems.contains(content.url) {
                                    expandedItems.remove(content.url)
                                } else {
                                    expandedItems.insert(content.url)
                                }
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }
}

struct SourceDetailRow: View {
    let content: ReviewedContent
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            HStack(alignment: .center, spacing: 12) {
                // Relevance indicator
                ZStack {
                    Circle()
                        .fill(content.isRelevant ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                        .frame(width: 32, height: 32)

                    Image(systemName: content.isRelevant ? "checkmark.circle.fill" : "minus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(content.isRelevant ? .green : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    // Title
                    Text(content.title ?? content.url.host ?? "Unknown")
                        .font(.headline)
                        .lineLimit(1)

                    // URL
                    Text(content.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Relevance badge
                Text(content.isRelevant ? "Relevant" : "Not Relevant")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(content.isRelevant ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .foregroundStyle(content.isRelevant ? .green : .secondary)
                    .clipShape(Capsule())

                // Open URL button
                Button(action: openURL) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)

                // Expand/Collapse button
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    // Extracted Information Section
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Extracted Information", systemImage: "doc.text")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        if content.extractedInfo.isEmpty {
                            Text("No information extracted")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .italic()
                        } else {
                            Text(content.extractedInfo)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Relevant Ranges Section
                    if !content.relevantRanges.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Relevant Ranges", systemImage: "text.line.first.and.arrowtriangle.forward")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)

                            Text(content.relevantRanges.map { "L\($0.lowerBound)-\($0.upperBound)" }.joined(separator: ", "))
                                .font(.caption)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Context Used Section
                    if !content.excerpts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Context Used in Final Response", systemImage: "doc.text.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)

                            ForEach(Array(content.excerpts.enumerated()), id: \.offset) { index, excerpt in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Excerpt \(index + 1)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.tertiary)
                                        if index < content.relevantRanges.count {
                                            let range = content.relevantRanges[index]
                                            Text("(L\(range.lowerBound)-\(range.upperBound))")
                                                .font(.caption)
                                                .fontDesign(.monospaced)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    ScrollView {
                                        Text(excerpt)
                                            .font(.caption)
                                            .fontDesign(.monospaced)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxHeight: 150)
                                }
                                .padding(8)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Judgment Section
                    VStack(alignment: .leading, spacing: 6) {
                        Label("LLM Judgment", systemImage: "brain")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Relevance")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                HStack(spacing: 4) {
                                    Image(systemName: content.isRelevant ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(content.isRelevant ? .green : .red)
                                    Text(content.isRelevant ? "Relevant to objective" : "Not relevant to objective")
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.leading, 44)
                .padding(.bottom, 8)
            }
        }
    }

    private func openURL() {
        #if os(macOS)
        NSWorkspace.shared.open(content.url)
        #else
        UIApplication.shared.open(content.url)
        #endif
    }
}

// MARK: - Details Tab

struct DetailsTab: View {
    let result: AggregatedResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Keywords Section
                DetailSection(title: "Keywords Used", icon: "key") {
                    FlowLayout(spacing: 8) {
                        ForEach(result.keywordsUsed, id: \.self) { keyword in
                            Text(keyword)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }

                // Questions Section
                DetailSection(title: "Research Questions", icon: "questionmark.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.questions, id: \.self) { question in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(question)
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                // Success Criteria Section
                DetailSection(title: "Success Criteria", icon: "checkmark.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.successCriteria, id: \.self) { criteria in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Text(criteria)
                                    .font(.subheadline)
                            }
                        }
                    }
                }

                // Statistics Section
                DetailSection(title: "Statistics", icon: "chart.bar") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("Total Pages Visited")
                                .foregroundStyle(.secondary)
                            Text("\(result.statistics.totalPagesVisited)")
                                .fontWeight(.medium)
                        }
                        GridRow {
                            Text("Relevant Pages Found")
                                .foregroundStyle(.secondary)
                            Text("\(result.statistics.relevantPagesFound)")
                                .fontWeight(.medium)
                        }
                        GridRow {
                            Text("Keywords Used")
                                .foregroundStyle(.secondary)
                            Text("\(result.statistics.keywordsUsed)")
                                .fontWeight(.medium)
                        }
                    }
                    .font(.subheadline)
                }
            }
            .padding()
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Debug Tab

struct DebugTab: View {
    let sentPrompts: [ResearchViewModel.SentPrompt]
    @State private var expandedPrompts: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if sentPrompts.isEmpty {
                    ContentUnavailableView {
                        Label("No Prompts", systemImage: "ladybug")
                    } description: {
                        Text("No prompts were recorded during this research session.")
                    }
                } else {
                    Text("LLM Prompts (\(sentPrompts.count))")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(sentPrompts) { prompt in
                        PromptCard(
                            prompt: prompt,
                            isExpanded: expandedPrompts.contains(prompt.id),
                            onToggle: {
                                if expandedPrompts.contains(prompt.id) {
                                    expandedPrompts.remove(prompt.id)
                                } else {
                                    expandedPrompts.insert(prompt.id)
                                }
                            }
                        )
                    }
                }
            }
            .padding()
        }
    }
}

struct PromptCard: View {
    let prompt: ResearchViewModel.SentPrompt
    let isExpanded: Bool
    let onToggle: () -> Void

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: prompt.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.phase)
                        .font(.headline)

                    Text(formattedTime)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(prompt.prompt.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())

                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            // Expanded Content
            if isExpanded {
                Divider()

                ScrollView {
                    Text(prompt.prompt)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(maxHeight: 400)
                .background(Color(.textBackgroundColor).opacity(0.5))

                // Copy button
                HStack {
                    Spacer()
                    Button(action: {
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(prompt.prompt, forType: .string)
                        #else
                        UIPasteboard.general.string = prompt.prompt
                        #endif
                    }) {
                        Label("Copy Prompt", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(Color(.controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            )
            subview.place(at: point, anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (positions, CGSize(width: totalWidth, height: currentY + lineHeight))
    }
}

#Preview {
    let sampleResult = AggregatedResult(
        objective: "Swift Concurrency best practices",
        questions: ["What is async/await?", "How to use actors?"],
        successCriteria: ["Find official documentation", "Find code examples"],
        reviewedContents: [
            ReviewedContent(
                url: URL(string: "https://developer.apple.com/swift")!,
                title: "Swift - Apple Developer",
                extractedInfo: "Swift is a powerful and intuitive programming language.",
                isRelevant: true
            )
        ],
        responseMarkdown: "# Swift Concurrency\n\nSwift provides modern concurrency features...",
        keywordsUsed: ["Swift concurrency", "async await", "actors"],
        statistics: AggregatedStatistics(
            totalPagesVisited: 25,
            relevantPagesFound: 8,
            keywordsUsed: 3,
            duration: .seconds(45)
        )
    )

    let samplePrompts = [
        ResearchViewModel.SentPrompt(phase: "Phase 1: Objective Analysis", prompt: "Sample prompt for objective analysis..."),
        ResearchViewModel.SentPrompt(phase: "Phase 5: Response Building", prompt: "Sample prompt for response building...")
    ]

    let sampleActivityLog = [
        ResearchViewModel.ActivityLogItem(type: .phaseStart, message: "Phase: Initial Search"),
        ResearchViewModel.ActivityLogItem(type: .search, message: "Searching: Swift concurrency"),
        ResearchViewModel.ActivityLogItem(type: .urlSuccess, message: "Swift - Apple Developer", url: URL(string: "https://developer.apple.com/swift")!)
    ]

    let sampleExplorationItems: [ResearchViewModel.ExplorationItem] = {
        var item = ResearchViewModel.ExplorationItem(url: URL(string: "https://developer.apple.com/swift")!)
        item.title = "Swift - Apple Developer"
        item.status = .success
        item.isRelevant = true
        item.extractedInfo = "Swift is a powerful programming language."
        item.duration = 1.5
        return [item]
    }()

    ResultView(
        result: sampleResult,
        sentPrompts: samplePrompts,
        activityLog: sampleActivityLog,
        explorationItems: sampleExplorationItems
    )
}
