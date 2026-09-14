import SwiftUI

/// Local-only poll creation fields, shown in `ComposeView` when `ComposeViewModel.isPollEnabled`.
/// Direct port of Android's `ui/compose/PollComposeSection.kt`.
struct PollComposeSection: View {
    @Bindable var viewModel: ComposeViewModel

    var body: some View {
        ForEach(Array(viewModel.pollOptions.indices), id: \.self) { index in
            HStack {
                TextField("Option \(index + 1)", text: optionBinding(index))
                if viewModel.pollOptions.count > ComposeViewModel.minPollOptions {
                    Button {
                        viewModel.removePollOption(at: index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if viewModel.pollOptions.count < ComposeViewModel.maxPollOptions {
            Button("Add option") { viewModel.addPollOption() }
        }

        Toggle("Multiple choice", isOn: $viewModel.pollMultiple)

        Picker("Poll duration", selection: $viewModel.pollExpiresInSeconds) {
            ForEach(ComposeViewModel.pollExpiryChoices, id: \.self) { seconds in
                Text(PollDuration.label(forSeconds: seconds)).tag(seconds)
            }
        }
    }

    private func optionBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { viewModel.pollOptions.indices.contains(index) ? viewModel.pollOptions[index] : "" },
            set: { newValue in
                guard viewModel.pollOptions.indices.contains(index) else { return }
                viewModel.pollOptions[index] = newValue
            }
        )
    }
}

/// Shared duration labels for `ComposeViewModel.pollExpiryChoices`, used both when composing a
/// poll and (indirectly, via the same seconds values) when displaying one.
enum PollDuration {
    static func label(forSeconds seconds: Int) -> String {
        switch seconds {
        case 300: return "5 minutes"
        case 1800: return "30 minutes"
        case 3600: return "1 hour"
        case 21600: return "6 hours"
        case 86400: return "1 day"
        case 259200: return "3 days"
        case 604800: return "1 week"
        case 2629746: return "1 month"
        default: return "\(seconds)s"
        }
    }
}
