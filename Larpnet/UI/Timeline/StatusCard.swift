import SwiftUI

/// One post in a timeline/thread. Direct port of Android's `ui/timeline/StatusCard.kt`.
/// Reblogs are unwrapped to show the reblogged status's content with a "boosted by" header,
/// same as Android -- `status.reblog` (not `status` itself) is what's actually rendered.
struct StatusCard: View {
    let status: Status
    var onOpenThread: (Status) -> Void = { _ in }
    var onOpenProfile: (String) -> Void = { _ in }
    var onReply: (Status) -> Void = { _ in }
    var onToggleFavourite: (Status) -> Void = { _ in }
    var onToggleReblog: (Status) -> Void = { _ in }
    var onToggleBookmark: (Status) -> Void = { _ in }

    private var displayed: Status { status.reblog ?? status }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if status.reblog != nil {
                Label {
                    Text("Boosted by \(status.account.displayName.isEmpty ? status.account.username : status.account.displayName)")
                } icon: {
                    Image(systemName: "arrow.2.squarepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .onTapGesture { onOpenProfile(status.account.id) }
            }

            HStack(alignment: .top) {
                Button { onOpenProfile(displayed.account.id) } label: {
                    AccountRow(account: displayed.account)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                VisibilityIcon(visibility: displayed.visibility)
                Text(RelativeTime.short(from: displayed.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if displayed.sensitive, !displayed.spoilerText.isEmpty {
                Text(displayed.spoilerText)
                    .font(.subheadline.weight(.medium))
            }

            if !(displayed.sensitive) || displayed.spoilerText.isEmpty {
                HTMLContentView(html: displayed.content)
            } else {
                DisclosureGroup("Show content") {
                    HTMLContentView(html: displayed.content)
                }
                .font(.subheadline)
            }

            if !displayed.mediaAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(displayed.mediaAttachments) { media in
                            RemoteImage(url: URL(string: media.previewUrl ?? media.url))
                                .frame(width: 160, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            HStack(spacing: 28) {
                Button { onReply(displayed) } label: {
                    Label("\(displayed.repliesCount)", systemImage: "bubble.right")
                }
                Button { onToggleReblog(displayed) } label: {
                    Label("\(displayed.reblogsCount)", systemImage: displayed.reblogged ? "arrow.2.squarepath.circle.fill" : "arrow.2.squarepath")
                }
                .tint(displayed.reblogged ? .green : .secondary)
                Button { onToggleFavourite(displayed) } label: {
                    Label("\(displayed.favouritesCount)", systemImage: displayed.favourited ? "star.fill" : "star")
                }
                .tint(displayed.favourited ? .yellow : .secondary)
                Button { onToggleBookmark(displayed) } label: {
                    Image(systemName: displayed.bookmarked ? "bookmark.fill" : "bookmark")
                }
                .tint(displayed.bookmarked ? .blue : .secondary)
                Spacer(minLength: 0)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { onOpenThread(displayed) }
        .larpnetCard()
    }
}
