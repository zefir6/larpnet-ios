import SwiftUI

/// One post in a timeline/thread. Direct port of Android's `ui/timeline/StatusCard.kt`.
/// Reblogs are unwrapped to show the reblogged status's content with a "boosted by" header,
/// same as Android -- `status.reblog` (not `status` itself) is what's actually rendered.
///
/// The "open thread" tap gesture is deliberately scoped to just the header+content block, not
/// the whole card: the action-button row and media thumbnails handle their own taps. Putting
/// `.onTapGesture` on the entire card (as an earlier version of this view did) meant every tap
/// anywhere in the card's bounds -- including on the tiny reply/reblog/favourite/bookmark
/// buttons -- competed with that ancestor gesture. Those buttons render at only ~13pt tall
/// (well under Apple's 44pt minimum tap target), so in practice most taps aimed at them missed
/// and landed on the card's shared hit-testing shape instead, silently doing nothing (confirmed
/// live: instrumenting the button's own action with a debug print showed it never fired).
/// Scoping the card-wide gesture away from that row, and padding each action button out to a
/// real tap target, fixes both the "favourite/reblog do nothing" report and, incidentally, why
/// tapping a media thumbnail just opened the post instead of enlarging it -- large tap areas
/// (images, the header block) always worked, only the undersized buttons didn't.
struct StatusCard: View {
    let status: Status
    var onOpenThread: (Status) -> Void = { _ in }
    var onOpenProfile: (String) -> Void = { _ in }
    var onReply: (Status) -> Void = { _ in }
    /// Toggle actions take the status's id, not a `Status` snapshot -- see
    /// `TimelineViewModel.toggleFavourite(id:)`'s doc comment for why a snapshot captured by
    /// this view's closures can't be trusted to reflect the current state.
    var onToggleFavourite: (String) -> Void = { _ in }
    var onToggleReblog: (String) -> Void = { _ in }
    var onToggleBookmark: (String) -> Void = { _ in }

    @State private var galleryContext: MediaGalleryContext?

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

            VStack(alignment: .leading, spacing: 8) {
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
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenThread(displayed) }

            if !displayed.mediaAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(displayed.mediaAttachments.enumerated()), id: \.element.id) { index, media in
                            RemoteImage(url: URL(string: media.previewUrl ?? media.url))
                                .frame(width: 160, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    galleryContext = MediaGalleryContext(
                                        attachments: displayed.mediaAttachments, initialIndex: index
                                    )
                                }
                        }
                    }
                }
            }

            HStack(spacing: 20) {
                actionButton(
                    count: displayed.repliesCount, systemImage: "bubble.right", isActive: false, tint: .secondary,
                    identifier: "reply-\(displayed.id)"
                ) { onReply(displayed) }
                actionButton(
                    count: displayed.reblogsCount,
                    systemImage: displayed.reblogged ? "arrow.2.squarepath.circle.fill" : "arrow.2.squarepath",
                    isActive: displayed.reblogged, tint: .green, identifier: "reblog-\(displayed.id)"
                ) { onToggleReblog(displayed.id) }
                actionButton(
                    count: displayed.favouritesCount,
                    systemImage: displayed.favourited ? "star.fill" : "star",
                    isActive: displayed.favourited, tint: .yellow, identifier: "favourite-\(displayed.id)"
                ) { onToggleFavourite(displayed.id) }
                actionButton(
                    count: nil,
                    systemImage: displayed.bookmarked ? "bookmark.fill" : "bookmark",
                    isActive: displayed.bookmarked, tint: .blue, identifier: "bookmark-\(displayed.id)"
                ) { onToggleBookmark(displayed.id) }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .larpnetCard()
        .fullScreenCover(item: $galleryContext) { context in
            MediaGalleryView(context: context)
        }
    }

    /// A real ~44pt-tall tap target (vs. the bare icon+text glyph bounds, which rendered at
    /// only ~13pt) plus a bounce on the SF Symbol when its active state flips -- the "no
    /// animation or visible reaction" this was missing. `identifier` is stable across the
    /// active/inactive icon swap (unlike matching on the SF Symbol name), so UI tests can find
    /// and tap a specific post's button without depending on its current state.
    @ViewBuilder
    private func actionButton(
        count: Int?, systemImage: String, isActive: Bool, tint: Color, identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .symbolEffect(.bounce, value: isActive)
                if let count {
                    Text("\(count)")
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(isActive ? tint : .secondary)
        .accessibilityIdentifier(identifier)
    }
}
