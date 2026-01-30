import SwiftUI
import SwiftResearch

struct ResultView: View {
    let result: ResearchAgent.Result
    @State private var selectedTab: ResultTab = .response

    enum ResultTab: String, CaseIterable {
        case response = "Response"
        case sources = "Sources"

        var icon: String {
            switch self {
            case .response: return "doc.text"
            case .sources: return "link"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ResultHeader(result: result)

            Divider()

            Picker("Tab", selection: $selectedTab) {
                ForEach(ResultTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            switch selectedTab {
            case .response:
                ResponseTab(answer: result.answer)
            case .sources:
                SourcesTab(visitedURLs: result.visitedURLs)
            }
        }
    }
}

// MARK: - Header

struct ResultHeader: View {
    let result: ResearchAgent.Result

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
                Label("\(result.visitedURLs.count) URLs", systemImage: "link")
                Label(formatDuration(result.duration), systemImage: "clock")
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
    let answer: String
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

                Text(answer)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
        #else
        UIPasteboard.general.string = answer
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
    let visitedURLs: [String]

    var body: some View {
        if visitedURLs.isEmpty {
            ContentUnavailableView {
                Label("No Sources", systemImage: "link")
            } description: {
                Text("No URLs were visited during the research.")
            }
        } else {
            List {
                ForEach(Array(visitedURLs.enumerated()), id: \.offset) { index, urlString in
                    SourceRow(urlString: urlString, index: index + 1)
                }
            }
            .listStyle(.inset)
        }
    }
}

struct SourceRow: View {
    let urlString: String
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                if let host = URL(string: urlString)?.host {
                    Text(host)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Text(urlString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let url = URL(string: urlString) {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let sampleResult = ResearchAgent.Result(
        objective: "Swift Concurrency best practices",
        answer: "# Swift Concurrency\n\nSwift provides modern concurrency features including async/await, actors, and structured concurrency.",
        visitedURLs: [
            "https://developer.apple.com/swift",
            "https://docs.swift.org/swift-book/LanguagGuide/Concurrency.html",
            "https://developer.apple.com/documentation/swift/concurrency"
        ],
        duration: .seconds(45)
    )

    ResultView(result: sampleResult)
}
