import SwiftUI

/// Avatar + display name + handle row, reused across timelines, directory, search, and
/// profile headers -- the counterpart of Android's `ui/common/AccountRow.kt`.
struct AccountRow: View {
    let account: Account
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: URL(string: account.avatar))
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName.isEmpty ? account.username : account.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("@\(account.acct.isEmpty ? account.username : account.acct)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
