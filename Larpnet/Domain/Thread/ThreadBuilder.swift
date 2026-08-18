import Foundation

/// A `Status` plus its already-resolved replies, sorted oldest-first. Direct port of Android's
/// `domain/thread/ThreadBuilder.kt`.
struct ThreadNode {
    let status: Status
    let children: [ThreadNode]
}

/// One row in a flattened thread view: a status plus how deeply nested its reply is, used for
/// indentation.
struct ThreadRow {
    let status: Status
    let depth: Int
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

    /// Flattens a `ThreadNode` tree into `(status, depth)` rows for a simple indented list,
    /// depth-first.
    static func flatten(_ node: ThreadNode, depth: Int = 0) -> [ThreadRow] {
        [ThreadRow(status: node.status, depth: depth)]
            + node.children.flatMap { flatten($0, depth: depth + 1) }
    }
}
