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
    /// When true, renders as a condensed row (no card chrome/clip/shadow, tighter padding) for
    /// use inside a shared outer panel -- `ThreadView`'s single-panel conversation layout. The
    /// default `false` preserves the normal per-post card look used by Timeline and Profile.
    var flat: Bool = false
    var onOpenThread: (Status) -> Void = { _ in }
    var onOpenProfile: (String) -> Void = { _ in }
    var onReply: (Status) -> Void = { _ in }
    /// Toggle actions take the status's id, not a `Status` snapshot -- see
    /// `TimelineViewModel.toggleFavourite(id:)`'s doc comment for why a snapshot captured by
    /// this view's closures can't be trusted to reflect the current state.
    var onToggleFavourite: (String) -> Void = { _ in }
    var onToggleReblog: (String) -> Void = { _ in }
    var onToggleBookmark: (String) -> Void = { _ in }
    /// Tag chip tapped, or an in-body hashtag link matching one of `status.tags` intercepted via
    /// `openURL` below -- both hand back the bare tag name (no leading `#`).
    var onOpenHashtag: (String) -> Void = { _ in }
    /// The logged-in user's own account id, used to gate the moderation context menu away from
    /// your own posts. `nil` (the default) is treated as "not own" -- the safe default for any
    /// caller that doesn't pass one, matching today's un-gated behavior.
    var currentAccountId: String? = nil
    /// Non-nil only on `ProfileView`'s own-profile screen -- the sole place a post can currently
    /// be deleted. `isOwnPost` already implies "this is a post `currentAccountId` authored", so
    /// folding Delete into this same `.contextMenu` (rather than a second `.contextMenu` layered
    /// on top by the caller) avoids two context-menu modifiers competing over the same view.
    var onDelete: ((Status) -> Void)? = nil

    @Environment(\.moderationActions) private var moderationActions
    @State private var galleryContext: MediaGalleryContext?

    private var displayed: Status { status.reblog ?? status }
    private var isOwnPost: Bool { currentAccountId != nil && currentAccountId == displayed.account.id }
    /// Whether there's anything for the "..." button / long-press menu to show at all -- used to
    /// hide the button entirely rather than offer a dead-end tap target when neither applies
    /// (e.g. `LocalPostListView`'s read-only rows, which attach no `.postModerationHost`).
    private var hasMenuContent: Bool {
        isOwnPost ? onDelete != nil : moderationActions != nil
    }

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

                if !displayed.tags.isEmpty {
                    tagChips
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenThread(displayed) }
            // Friendica already emits hashtags as inline `<a href>` anchors inside a post's
            // HTML body, which `HTMLContentView` renders as tappable `AttributedString` links --
            // without this, tapping one falls through to the system default and opens Safari,
            // while the tag chip row below opens the in-app hashtag timeline for the exact same
            // tag. Intercepting here makes both affordances behave identically; anything that
            // isn't a recognized tag link (mentions, external URLs) still falls through to
            // `.systemAction`, unchanged from today.
            .environment(\.openURL, OpenURLAction { url in
                guard let tag = displayed.tags.first(where: { $0.url == url.absoluteString }) else {
                    return .systemAction
                }
                onOpenHashtag(tag.name)
                return .handled
            })

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
                    count: nil, systemImage: "arrowshape.turn.up.left", isActive: false, tint: .secondary,
                    identifier: "reply-\(displayed.id)"
                ) { onReply(displayed) }
                actionButton(
                    count: displayed.repliesCount, systemImage: "bubble.right", isActive: false, tint: .secondary,
                    identifier: "open-thread-\(displayed.id)"
                ) { onOpenThread(displayed) }
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
                // An explicit, always-visible tap target for moderation, not just a long-press
                // context menu -- long press discoverability is poor (nothing on the card hints
                // it's there), so this "..." button in the row's trailing/bottom-right corner is
                // the primary way in; the `.contextMenu` below stays as a secondary shortcut for
                // anyone used to that gesture, sharing the exact same menu content.
                if hasMenuContent {
                    Menu {
                        moderationMenuItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .padding(.vertical, 12)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                    }
                    .tint(.secondary)
                    .accessibilityIdentifier("more-\(displayed.id)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .modifier(CardChrome(flat: flat))
        .fullScreenCover(item: $galleryContext) { context in
            MediaGalleryView(context: context)
        }
        .contextMenu {
            moderationMenuItems
        }
    }

    /// Delete (own posts) or hide/block/report (everyone else's) -- shared between the
    /// always-visible "..." button and the long-press `.contextMenu`, so both trigger the exact
    /// same actions. Gated on both `moderationActions` being present (screens like the
    /// Hidden/Blocked Posts and Following lists render `StatusCard` with no
    /// `.postModerationHost` attached, so there's nothing to hide/block/report from there) and
    /// `!isOwnPost` -- never offer "Block yourself"/"Report yourself".
    @ViewBuilder
    private var moderationMenuItems: some View {
        if isOwnPost {
            if let onDelete {
                Button("Delete", role: .destructive) { onDelete(displayed) }
            }
        } else if let actions = moderationActions {
            Button("Hide post") { actions.hide(displayed.id) }
            Button("Block post", role: .destructive) { actions.requestBlockPost(displayed.id, displayed.account.id) }
            Divider()
            Button("Block @\(displayed.account.acct)", role: .destructive) { actions.blockAccount(displayed.account.id) }
            Button("Report post\u{2026}") { actions.requestReportPost(displayed.id, displayed.account.id, displayed.account.acct) }
            Button("Report @\(displayed.account.acct)\u{2026}") { actions.requestReportAccount(displayed.account.id, displayed.account.acct) }
        }
    }

    /// Read-only capsule chips surfacing the hashtags Friendica already attached to this post
    /// (`Status.tags`) -- visually similar to `TagsSectionView`'s compose-time chip, but not
    /// shared code with it: that one is interactive/selection-oriented for choosing tags to
    /// post with, this one is a plain tap-to-open-hashtag-timeline button. Small enough that
    /// forcing a shared abstraction between the two isn't worth it.
    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(displayed.tags, id: \.name) { tag in
                    Button {
                        onOpenHashtag(tag.name)
                    } label: {
                        Text("#\(tag.name)")
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(LarpnetTheme.pageBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// `flat` mode drops the card's own background/clip/shadow and outer padding in favor of
    /// tighter row-only padding, so it reads as one condensed row sharing a parent panel's
    /// chrome (`ThreadView`'s single outer `.larpnetCard()`) instead of nesting a shadowed card
    /// inside a card.
    private struct CardChrome: ViewModifier {
        let flat: Bool

        func body(content: Content) -> some View {
            if flat {
                content.padding(.horizontal, 16).padding(.vertical, 10)
            } else {
                content.padding(10).larpnetCard()
            }
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
