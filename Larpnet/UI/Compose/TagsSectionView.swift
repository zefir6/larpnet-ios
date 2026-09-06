import SwiftUI

/// Direct port of Android's `ui/compose/TagsSection.kt`: predefined + recent tags as toggleable
/// chips, plus freetext entry for anything else. SwiftUI has no first-party flow layout before
/// wrapping the `Layout` protocol (overkill for a short, largely-static chip list), so this uses
/// an adaptive `LazyVGrid` instead of Compose's `FlowRow` -- visually similar, simpler to build.
struct TagsSectionView: View {
    @Bindable var viewModel: ComposeViewModel

    private static let columns = [GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 8) {
                ForEach(viewModel.toggleableTags, id: \.self) { tag in
                    chip(for: tag, isSelected: viewModel.selectedTags.contains(tag)) {
                        viewModel.toggleTag(tag)
                    }
                }
                ForEach(viewModel.customTags, id: \.self) { tag in
                    chip(for: tag, isSelected: viewModel.selectedTags.contains(tag)) {
                        viewModel.toggleTag(tag)
                    }
                }
            }

            HStack {
                TextField("Add tag", text: $viewModel.customTagInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { viewModel.addCustomTag() }
                Button("Add") { viewModel.addCustomTag() }
                    .disabled(viewModel.customTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // `.buttonStyle(.plain)` + `.contentShape(Rectangle())` are load-bearing here, not
    // cosmetic -- this view sits inside `ComposeView`'s `Form`, and a `Form`/`List` row's own
    // selection gesture silently swallows a nested `Button`'s tap otherwise (see
    // `SettingsView.swift`'s doc comment for the confirmed-live version of this bug).
    private func chip(for tag: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("#\(tag)")
                .font(.footnote)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(isSelected ? LarpnetTheme.accent : LarpnetTheme.pageBackground)
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
