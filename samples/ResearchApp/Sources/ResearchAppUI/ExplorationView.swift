import SwiftUI
import SwiftResearch

/// View showing research in progress
public struct ExplorationView: View {
    let viewModel: ResearchViewModel

    public init(viewModel: ResearchViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated progress indicator
            ProgressView()
                .scaleEffect(1.5)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                Text("Researching...")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(viewModel.objective)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 40)
            }

            Text("The agent is autonomously searching the web and analyzing information.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let viewModel = ResearchViewModel()
    ExplorationView(viewModel: viewModel)
}
