import SwiftUI

/// Renders a poll's options -- a vote form when the current user hasn't voted yet and the poll
/// hasn't expired, or read-only result bars otherwise. Local-only (see `Poll`'s doc comment):
/// `onVote` always votes against this instance's own tally. Direct port of Android's
/// `ui/common/PollView.kt`.
struct PollView: View {
    let poll: Poll
    let onVote: ([Int]) -> Void

    @State private var selectedSingle: Int?
    @State private var selectedMultiple: Set<Int> = []

    private var showResults: Bool { poll.voted || poll.expired }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                if showResults {
                    resultRow(index: index, option: option)
                } else {
                    voteRow(index: index, option: option)
                }
            }

            if showResults {
                HStack(spacing: 4) {
                    Text("\(poll.votesCount) votes")
                    if poll.expired {
                        Text("· Poll ended")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Button("Vote") {
                    onVote(currentChoices)
                }
                .disabled(currentChoices.isEmpty)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.top, 4)
        .onChange(of: poll.id) {
            selectedSingle = nil
            selectedMultiple = []
        }
    }

    private var currentChoices: [Int] {
        poll.multiple ? Array(selectedMultiple) : selectedSingle.map { [$0] } ?? []
    }

    @ViewBuilder
    private func voteRow(index: Int, option: PollOption) -> some View {
        Button {
            if poll.multiple {
                if selectedMultiple.contains(index) { selectedMultiple.remove(index) } else { selectedMultiple.insert(index) }
            } else {
                selectedSingle = index
            }
        } label: {
            HStack {
                Image(systemName: selectionIcon(index))
                Text(option.title)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func selectionIcon(_ index: Int) -> String {
        if poll.multiple {
            return selectedMultiple.contains(index) ? "checkmark.square.fill" : "square"
        }
        return selectedSingle == index ? "largecircle.fill.circle" : "circle"
    }

    @ViewBuilder
    private func resultRow(index: Int, option: PollOption) -> some View {
        let percent = poll.votesCount > 0 ? (option.votesCount ?? 0) * 100 / poll.votesCount : 0
        let ownVote = poll.ownVotes?.contains(index) == true
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(option.title)
                    .fontWeight(ownVote ? .bold : .regular)
                Spacer(minLength: 0)
                Text("\(percent)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(percent), total: 100)
        }
    }
}
