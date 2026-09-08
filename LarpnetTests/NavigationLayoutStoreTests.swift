import XCTest
@testable import Larpnet

/// Covers `NavigationLayoutStore`'s pure partition-validation and parsing logic -- kept
/// `static`/host-independent so these don't touch `UserDefaults.standard`. The two-list
/// partition invariant (every `AppDestination` lives in exactly one of `bottomBar`/`menu`) is
/// new complexity this store adds over the single-permutation check the `BottomNavOrderStore`
/// it replaces used, so it's worth covering directly.
final class NavigationLayoutStoreTests: XCTestCase {
    func testDefaultBarAndMenuFormAValidPartition() {
        XCTAssertTrue(NavigationLayoutStore.isValidPartition(bar: AppDestination.defaultBottomBar, menu: AppDestination.defaultMenu))
    }

    func testPartitionRejectsAMissingDestination() {
        let bar = Array(AppDestination.defaultBottomBar.dropLast())
        XCTAssertFalse(NavigationLayoutStore.isValidPartition(bar: bar, menu: AppDestination.defaultMenu))
    }

    func testPartitionRejectsADuplicatedDestination() {
        let bar = AppDestination.defaultBottomBar + [AppDestination.defaultMenu[0]]
        XCTAssertFalse(NavigationLayoutStore.isValidPartition(bar: bar, menu: AppDestination.defaultMenu))
    }

    func testParseDropsUnknownRawValues() {
        XCTAssertEqual(NavigationLayoutStore.parse("home,not_a_real_destination,local"), [.home, .local])
    }

    func testParseOfEmptyStringIsEmpty() {
        XCTAssertEqual(NavigationLayoutStore.parse(""), [])
    }
}
