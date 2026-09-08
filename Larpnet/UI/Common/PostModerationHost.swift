import SwiftUI

/// Identifies what a report sheet targets -- an account alone (`statusIds` empty) or a specific
/// post by that account (`statusIds: [id]`). One sheet serves both report flows.
struct ReportTarget: Identifiable {
    let accountId: String
    let statusIds: [String]
    let handle: String

    var id: String { statusIds.first ?? accountId }
}

/// Closures `StatusCard`'s context menu invokes, injected via `@Environment` rather than added
/// as five more closure props on `StatusCard` (on top of the six it already has) -- these five
/// need to drive shared modal state (`PostModerationHost`'s confirmation dialog and report
/// sheet) that lives at the screen root, not per-card, so environment injection is a deliberate,
/// narrow deviation from `StatusCard`'s usual closure-prop convention, not a new house style.
///
/// Optional in the environment (default `nil`) so `StatusCard` instances rendered without a
/// `.postModerationHost` attached (the Hidden/Blocked/Following list screens) simply omit the
/// moderation menu items instead of wiring up no-ops that look like they do something.
///
/// `@unchecked Sendable`, not plain `Sendable` -- these closures are ordinary (non-`@Sendable`)
/// ones built from `@MainActor`-isolated SwiftUI view code, but every access (constructing this
/// struct in `PostModerationHost.body`, reading it back out of `@Environment` in
/// `StatusCard.body`) happens on the main actor, same rationale as `AppContainer`'s own
/// `@unchecked Sendable` conformance. Required because `EnvironmentKey.defaultValue` must be
/// `Sendable` under Swift 6 strict concurrency.
struct ModerationActions: @unchecked Sendable {
    let hide: (String) -> Void
    let requestBlockPost: (String, String) -> Void
    let blockAccount: (String) -> Void
    let requestReportPost: (String, String, String) -> Void
    let requestReportAccount: (String, String) -> Void
}

private struct ModerationActionsKey: EnvironmentKey {
    static let defaultValue: ModerationActions? = nil
}

extension EnvironmentValues {
    var moderationActions: ModerationActions? {
        get { self[ModerationActionsKey.self] }
        set { self[ModerationActionsKey.self] = newValue }
    }
}

/// Owns the confirmation-dialog and report-sheet presentation state shared by every screen that
/// renders `StatusCard`s (Timeline, Thread, Profile). Attached once per screen root -- not
/// per-row -- since `.confirmationDialog`/`.sheet` state living inside a `ForEach` would
/// duplicate across every card in the list.
struct PostModerationHost: ViewModifier {
    @State private var blockPostCandidate: (id: String, accountId: String)?
    @State private var reportTarget: ReportTarget?

    let onHidePost: (String) -> Void
    let onBlockPost: (String) -> Void
    let onBlockAccount: (String) -> Void
    let onSubmitReport: (ReportTarget, String, String?) -> Void

    func body(content: Content) -> some View {
        content
            // `.confirmationDialog` has no `item:` overload -- `isPresented:` bound to a
            // computed Binding off the optional candidate is the correct shape here, not a
            // second `@State Bool` that could drift out of sync with `blockPostCandidate`.
            .confirmationDialog(
                "Block this post?",
                isPresented: Binding(
                    get: { blockPostCandidate != nil },
                    set: { if !$0 { blockPostCandidate = nil } }
                ),
                presenting: blockPostCandidate
            ) { candidate in
                Button("Block post", role: .destructive) {
                    onBlockPost(candidate.id)
                    blockPostCandidate = nil
                }
                Button("Block and report\u{2026}", role: .destructive) {
                    onBlockPost(candidate.id)
                    reportTarget = ReportTarget(accountId: candidate.accountId, statusIds: [candidate.id], handle: "")
                    blockPostCandidate = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Hides this post from your view and remembers it as blocked. This never notifies the poster.")
            }
            .sheet(item: $reportTarget) { target in
                ReportSheet(target: target) { category, comment in
                    onSubmitReport(target, category, comment)
                }
            }
            .environment(
                \.moderationActions,
                ModerationActions(
                    hide: onHidePost,
                    requestBlockPost: { id, accountId in blockPostCandidate = (id, accountId) },
                    blockAccount: onBlockAccount,
                    requestReportPost: { id, accountId, handle in
                        reportTarget = ReportTarget(accountId: accountId, statusIds: [id], handle: handle)
                    },
                    requestReportAccount: { accountId, handle in
                        reportTarget = ReportTarget(accountId: accountId, statusIds: [], handle: handle)
                    }
                )
            )
    }
}

extension View {
    func postModerationHost(
        onHidePost: @escaping (String) -> Void,
        onBlockPost: @escaping (String) -> Void,
        onBlockAccount: @escaping (String) -> Void,
        onSubmitReport: @escaping (ReportTarget, String, String?) -> Void
    ) -> some View {
        modifier(PostModerationHost(
            onHidePost: onHidePost, onBlockPost: onBlockPost, onBlockAccount: onBlockAccount,
            onSubmitReport: onSubmitReport
        ))
    }
}
