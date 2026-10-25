import XCTest
@testable import Larpnet

/// Covers `NavigationLayoutStore`'s pure partition-validation and parsing logic -- kept
/// `static`/host-independent so these don't touch `UserDefaults.standard`. The two-list
/// partition invariant (every customizable `AppDestination` lives in exactly one of
/// `bottomBar`/`topBar`/`more`) is new complexity this store adds over the single-permutation check the `BottomNavOrderStore`
/// it replaces used, so it's worth covering directly.
final class NavigationLayoutStoreTests: XCTestCase {
    func testDefaultBarTopAndMoreFormAValidPartition() {
        XCTAssertTrue(NavigationLayoutStore.isValidPartition(
            bar: AppDestination.defaultBottomBar, top: AppDestination.defaultTopBar, more: AppDestination.defaultMore))
    }

    func testPartitionRejectsAMissingDestination() {
        let bar = Array(AppDestination.defaultBottomBar.dropLast())
        XCTAssertFalse(NavigationLayoutStore.isValidPartition(
            bar: bar, top: AppDestination.defaultTopBar, more: AppDestination.defaultMore))
    }

    func testPartitionRejectsADuplicatedDestination() {
        let bar = AppDestination.defaultBottomBar + [AppDestination.defaultMore[0]]
        XCTAssertFalse(NavigationLayoutStore.isValidPartition(
            bar: bar, top: AppDestination.defaultTopBar, more: AppDestination.defaultMore))
    }

    func testPartitionRejectsADestinationInTwoLists() {
        let top = AppDestination.defaultTopBar + [AppDestination.defaultBottomBar[0]]
        XCTAssertFalse(NavigationLayoutStore.isValidPartition(
            bar: AppDestination.defaultBottomBar, top: top, more: AppDestination.defaultMore))
    }

    func testParseDropsUnknownRawValues() {
        XCTAssertEqual(NavigationLayoutStore.parse("home,not_a_real_destination,local"), [.home, .local])
    }

    func testParseOfEmptyStringIsEmpty() {
        XCTAssertEqual(NavigationLayoutStore.parse(""), [])
    }
}
