import XCTest
@testable import Larpnet

/// Covers `ThreadBuilder.filterExcluded(_:excludedStatusIds:excludedAccountIds:)` -- the
/// hide/block-post and block-account filtering `ThreadViewModel.refreshDescendants()` applies
/// *after* `ThreadBuilder.flatten` runs, never by pruning the `ThreadNode` tree beforehand.
/// Pruning pre-tree would orphan a hidden/blocked node's children (they'd never be marked
/// `known` in `ThreadBuilder.buildTree`'s worklist); this proves the post-flatten approach
/// avoids that -- a filtered-out row disappears, but its children remain, at their original
/// depth.
final class ThreadFilteringTests: XCTestCase {
    private func makeStatus(_ id: String, accountId: String = "acct-default") -> Status {
        Status(id: id, createdAt: Date(), account: Account(id: accountId))
    }

    func testHiddenMidTreeNodeDisappearsButChildrenSurviveAtOriginalDepth() {
        let root = ThreadNode(status: makeStatus("root"), children: [
            ThreadNode(status: makeStatus("a"), children: [
                ThreadNode(status: makeStatus("a1"), children: []),
            ]),
            ThreadNode(status: makeStatus("b"), children: []),
        ])
        let rows = ThreadBuilder.flatten(root, collapsedIds: [])
        let filtered = ThreadBuilder.filterExcluded(rows, excludedStatusIds: ["a"])

        XCTAssertEqual(filtered.map(\.status.id), ["a1", "b"])
        XCTAssertEqual(filtered.first { $0.status.id == "a1" }?.depth, 1, "child keeps its original depth even though its parent row was dropped")
    }

    func testBlockedAccountDropsAllItsReplies() {
        let root = ThreadNode(status: makeStatus("root"), children: [
            ThreadNode(status: makeStatus("a", accountId: "spammer"), children: []),
            ThreadNode(status: makeStatus("b", accountId: "friend"), children: []),
        ])
        let rows = ThreadBuilder.flatten(root, collapsedIds: [])
        let filtered = ThreadBuilder.filterExcluded(rows, excludedStatusIds: [], excludedAccountIds: ["spammer"])

        XCTAssertEqual(filtered.map(\.status.id), ["b"])
    }

    func testNoExclusionsLeavesEveryRowUntouched() {
        let root = ThreadNode(status: makeStatus("root"), children: [
            ThreadNode(status: makeStatus("a"), children: []),
        ])
        let rows = ThreadBuilder.flatten(root, collapsedIds: [])
        let filtered = ThreadBuilder.filterExcluded(rows, excludedStatusIds: [])

        XCTAssertEqual(filtered.map(\.status.id), rows.map(\.status.id))
    }
}
