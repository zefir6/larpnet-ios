import Foundation

/// A `Status` plus its already-resolved replies, sorted oldest-first. Direct port of Android's
/// `domain/thread/ThreadBuilder.kt`.
struct ThreadNode {
    let status: Status
    let children: [ThreadNode]
}

/// One row in a flattened, collapse-aware thread view. `depth` starts at 0 for a direct reply to
/// the focus post (the root `ThreadNode` passed to `flatten` is never itself emitted as a row --
/// see `flatten(_:collapsedIds:)`). `hiddenDescendantCount` is the size of the *entire* collapsed
/// subtree, not just direct children, so a "N replies" hint reflects what re-expanding reveals.
struct ThreadRenderItem {
    let status: Status
    let depth: Int
    let hasChildren: Bool
    let isCollapsed: Bool
    let hiddenDescendantCount: Int
}

enum ThreadBuilder {
    /// `GET /api/v1/statuses/{id}/context` returns `descendants` as a **flat list**, ordered by
    /// uri-id across the whole subtree -- not a nested tree -- and a parent can appear later in
    /// the array than its own child. This reconstructs the actual reply tree.
    ///
    /// Algorithm (a worklist/BFS-with-stall-counter, identical to the Kotlin original): start
    /// with a `known` set seeded with the focus status's id and a `childrenByParentID`
    /// dictionary. Repeatedly pop the front candidate from the remaining descendants: if its
    /// `inReplyToId` is already `known`, attach it under that parent and add its own id to
    /// `known` (reset the stall counter); otherwise push it to the back and increment the
    /// stall counter. Stop once a full pass attaches nothing -- anything left is orphaned (its
    /// parent isn't present in this context, e.g. was deleted).
    static func buildTree(focus: Status, descendants: [Status]) -> ThreadNode {
        var known: Set<String> = [focus.id]
        var childrenByParentID: [String: [Status]] = [:]
        var remaining = descendants
        var stalled = 0

        while !remaining.isEmpty, stalled < remaining.count {
            let candidate = remaining.removeFirst()
            if let parentID = candidate.inReplyToId, known.contains(parentID) {
                childrenByParentID[parentID, default: []].append(candidate)
                known.insert(candidate.id)
                stalled = 0
            } else {
                remaining.append(candidate)
                stalled += 1
            }
        }

        func node(for status: Status) -> ThreadNode {
            let children = (childrenByParentID[status.id] ?? [])
                .sorted { $0.createdAt < $1.createdAt }
                .map(node(for:))
            return ThreadNode(status: status, children: children)
        }

        return node(for: focus)
    }

    /// Flattens `root`'s children (never `root` itself -- the caller already renders the focus
    /// post separately) into a collapse-aware, depth-first row list. A node whose id is in
    /// `collapsedIds` emits only itself, with `hiddenDescendantCount` covering its whole
    /// subtree; an expanded node emits itself followed by its flattened children one level
    /// deeper. Direct replies to `root` land at depth 0.
    static func flatten(_ root: ThreadNode, collapsedIds: Set<String>) -> [ThreadRenderItem] {
        root.children.flatMap { flattenNode($0, depth: 0, collapsedIds: collapsedIds) }
    }

    private static func flattenNode(_ node: ThreadNode, depth: Int, collapsedIds: Set<String>) -> [ThreadRenderItem] {
        let isCollapsed = collapsedIds.contains(node.status.id)
        let item = ThreadRenderItem(
            status: node.status,
            depth: depth,
            hasChildren: !node.children.isEmpty,
            isCollapsed: isCollapsed,
            hiddenDescendantCount: isCollapsed ? countDescendants(node) : 0
        )
        guard !isCollapsed else { return [item] }
        return [item] + node.children.flatMap { flattenNode($0, depth: depth + 1, collapsedIds: collapsedIds) }
    }

    private static func countDescendants(_ node: ThreadNode) -> Int {
        node.children.count + node.children.reduce(0) { $0 + countDescendants($1) }
    }
}
