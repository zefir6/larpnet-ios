import SwiftUI

/// Reusable report form -- category + optional comment -- for both post reports
/// (`target.statusIds == [id]`) and account-only reports (`target.statusIds == []`). The app's
/// first `.sheet`-presented `Form`/picker of this shape; there's no existing file to model it
/// after beyond the general `.sheet(item:)` convention `ComposeContext`/`MediaGalleryContext`
/// already use.
struct ReportSheet: View {
    let target: ReportTarget
    let onSubmit: (_ category: String, _ comment: String?) -> Void

    @State private var category = "spam"
    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""

    private static let categories = [
        ("spam", "Spam"),
        ("violation", "Rule violation"),
        ("other", "Other"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        target.statusIds.isEmpty
                            ? "Report @\(target.handle)"
                            : "Report post by @\(target.handle)"
                    )
                    .font(.subheadline)
                }
                Section("Reason") {
                    Picker("Category", selection: $category) {
                        ForEach(Self.categories, id: \.0) { key, label in
                            Text(label).tag(key)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section("Additional details (optional)") {
                    TextField("Comment", text: $comment, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSubmit(category, trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
            }
        }
    }
}
