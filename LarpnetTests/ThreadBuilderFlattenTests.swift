import XCTest
@testable import Larpnet

/// Covers `ThreadBuilder.flatten(_:collapsedIds:)` directly, as a pure function over hand-built
/// `ThreadNode` trees -- the one place among the collapsible-thread-view changes where a unit
/// test earns its keep, since a regression here (e.g. reintroducing the old flattener's
/// root-at-depth-0 baseline) would silently mis-indent every reply in the app.
final class ThreadBuilderFlattenTests: XCTestCase {
    private func makeStatus(_ id: String) -> Status {
        Status(id: id, createdAt: Date(), account: Account(id: "acct-\(id)"))
    }

    func testDirectRepliesStartAtDepthZero() {
        let root = ThreadNode(status: makeStatus("root"), children: [
            ThreadNode(status: makeStatus("a"), children: []),
            ThreadNode(status: makeStatus("b"), children: []),
        ])
        let rows = ThreadBuilder.flatten(root, collapsedIds: [])
        XCTAssertEqual(rows.map(\.status.id), ["a", "b"])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }

    func testExpandedChildrenNestOneDepthDeeper() {
        let root = ThreadNode(status: makeStatus("root"), children: [
            ThreadNode(status: makeStatus("a"), children: [
                ThreadNode(status: makeStatus("a1"), children: []),
            ]),
        ])
        let rows = ThreadBuilder.flatten(root, collapsedIds: [])
        XCTAssertEqual(rows.map(\.status.id), ["a", "a1"])
        XCTAssertEqual(rows.map(\.depth), [0, 1])
    }

    func testCollapsedNodeHidesItsFullSubtreeAndReportsTotalCount() {
        let root = ThreadNode(status: makeStatus("root"), children: [
            ThreadNode(status: makeStatus("a"), children: [
                ThreadNode(status: makeStatus("a1"), children: [
                    ThreadNode(status: makeStatus("a1x"), children: []),
                ]),
                ThreadNode(status: makeStatus("a2"), children: []),
            ]),
            ThreadNode(status: makeStatus("b"), children: []),
        ])
        let rows = ThreadBuilder.flatten(root, collapsedIds: ["a"])
        // "a"'s subtree (a1, a1x, a2 -- 3 total) is hidden; "b" is unaffected.
        XCTAssertEqual(rows.map(\.status.id), ["a", "b"])
        let aRow = rows.first { $0.status.id == "a" }
        XCTAssertEqual(aRow?.isCollapsed, true)
        XCTAssertEqual(aRow?.hiddenDescendantCount, 3)
    }

    func testLeafNodeReportsNoChildren() {
        let root = ThreadNode(status: makeStatus("root"), children: [
            ThreadNode(status: makeStatus("a"), children: []),
        ])
        let rows = ThreadBuilder.flatten(root, collapsedIds: [])
        XCTAssertEqual(rows.first?.hasChildren, false)
    }
}
