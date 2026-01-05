import SwiftUI
import SwiftResearch

/// View showing real-time URL exploration progress
public struct ExplorationView: View {
    let viewModel: ResearchViewModel

    public init(viewModel: ResearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with current phase and stats
            ExplorationHeader(viewModel: viewModel)

            Divider()

            // Keywords section
            if !viewModel.keywords.isEmpty {
                KeywordsSection(
                    keywords: viewModel.keywords,
                    currentKeyword: viewModel.currentKeyword
                )
                Divider()
            }

            // URL exploration list
            if viewModel.explorationItems.isEmpty {
                ContentUnavailableView {
                    Label("Waiting for URLs", systemImage: "magnifyingglass")
                } description: {
                    Text("URLs will appear here as they are discovered")
                }
            } else {
                ExplorationList(items: viewModel.explorationItems)
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

    var body: some View {
        List {
            // Processing items first
            let processingItems = items.filter { $0.status == .processing }
            let completedItems = items.filter { $0.status != .processing && $0.status != .queued }
            let queuedItems = items.filter { $0.status == .queued }

            if !processingItems.isEmpty {
                Section("Processing") {
                    ForEach(processingItems) { item in
                        ExplorationItemRow(item: item)
                    }
                }
            }

            if !completedItems.isEmpty {
                Section("Completed (\(completedItems.count))") {
                    ForEach(completedItems.reversed()) { item in
                        ExplorationItemRow(item: item)
                    }
                }
            }

            if !queuedItems.isEmpty {
                Section("Queued (\(queuedItems.count))") {
                    ForEach(queuedItems.prefix(10)) { item in
                        ExplorationItemRow(item: item)
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
    }
}

// MARK: - Flow Layout (reused from ResultView)

struct ExplorationFlowLayout: Layout {
    var spacing: CGFloat = 6

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
    let viewModel = ResearchViewModel()
    ExplorationView(viewModel: viewModel)
}
