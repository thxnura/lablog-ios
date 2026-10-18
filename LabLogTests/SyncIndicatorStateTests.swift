import XCTest
@testable import LabLog

/// The toolbar sync indicator: quiet when everything is fine, specific when it isn't.
final class SyncIndicatorStateTests: XCTestCase {
    private func state(configured: Bool = true, online: Bool = true,
                       _ status: SyncEngine.Status = .idle, pending: Int = 0) -> SyncIndicatorState {
        SyncIndicatorState(isConfigured: configured, isOnline: online, status: status, pendingCount: pending)
    }

    func testCalmWhenEverythingIsSynced() {
        let s = state()
        XCTAssertEqual(s, .synced)
        XCTAssertNil(s.shortText, "no 'Online' label in the normal state")
        XCTAssertFalse(s.showsCount)
    }

    func testOfflineWinsAndSaysSo() {
        // Live reachability beats a stale engine status.
        let s = state(online: false, .syncing, pending: 2)
        XCTAssertEqual(s, .offline)
        XCTAssertEqual(s.shortText, "Offline")
        XCTAssertTrue(s.detail(pending: 2).contains("2 records are saved on this iPhone"))
        XCTAssertNil(s.action, "nothing to do offline but keep working")
    }

    func testWaitingFailedAndSignedOut() {
        XCTAssertEqual(state(pending: 1), .waiting)
        XCTAssertEqual(state(pending: 1).title(pending: 1), "1 record waiting to upload")
        XCTAssertEqual(state(pending: 1).action, .syncNow)
        XCTAssertEqual(state(.failed("Server returned 500"), pending: 1).action, .syncNow)
        XCTAssertEqual(state(.signedOut, pending: 3), .signedOut)
        XCTAssertEqual(state(.signedOut, pending: 3).action, .signIn, "signed out: the popover offers Sign in")
        XCTAssertEqual(state(.signedOut, pending: 1).detail(pending: 1),
                       "1 record is saved on this iPhone. Sign in to upload it.")
        XCTAssertEqual(state(.signedOut, pending: 0), .synced, "nothing waiting, nothing to nag about")
    }

    func testOnDeviceBuild() {
        XCTAssertEqual(state(configured: false, online: false, pending: 4), .onDevice)
    }
}
