import AppKit
import Carbon
import ServiceManagement
import XCTest
@testable import EasyTile

@MainActor final class FakeLoginItem: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var afterRegister: SMAppService.Status = .enabled
    var fail = false
    var registered = 0, unregistered = 0, settingsOpened = 0
    func register() throws {
        registered += 1
        if fail { throw NSError(domain: "Test", code: 1) }
        status = afterRegister
    }
    func unregister() throws {
        unregistered += 1
        if fail { throw NSError(domain: "Test", code: 2) }
        status = .notRegistered
    }
    func openSettings() { settingsOpened += 1 }
}

@MainActor final class LoginLaunchTests: XCTestCase {
    func testReadingStatusDoesNotRegisterAnything() {
        let service = FakeLoginItem()
        let login = LoginLaunch(service: service)
        XCTAssertFalse(login.enabled)
        XCTAssertEqual(service.registered, 0)
        for status in [SMAppService.Status.enabled, .requiresApproval, .notFound, .notRegistered] {
            service.status = status; login.refresh()
            XCTAssertEqual(login.enabled, status == .enabled)
            XCTAssertEqual(login.requiresApproval, status == .requiresApproval)
        }
    }
    func testEnableDisableIsIdempotentAndFollowsTheSystem() {
        let service = FakeLoginItem()
        // Exercise one instance with the same service across each transition.
        let subject = LoginLaunch(service: service)
        subject.setEnabled(true); subject.setEnabled(true)
        XCTAssertTrue(subject.enabled); XCTAssertEqual(service.registered, 1)
        subject.setEnabled(false); subject.setEnabled(false)
        XCTAssertFalse(subject.enabled); XCTAssertEqual(service.unregistered, 1)
    }
    func testPendingApprovalIsNeverShownAsEnabled() {
        let service = FakeLoginItem(); service.afterRegister = .requiresApproval
        let login = LoginLaunch(service: service)
        login.setEnabled(true)
        XCTAssertFalse(login.enabled); XCTAssertTrue(login.requiresApproval)
        login.setEnabled(true)
        XCTAssertEqual(service.settingsOpened, 1); XCTAssertEqual(service.registered, 1)
        service.status = .enabled; login.refresh()
        XCTAssertTrue(login.enabled)
    }
    func testFailedRegistrationLeavesSwitchOffAndCanBeRetried() {
        let service = FakeLoginItem(); service.fail = true
        let login = LoginLaunch(service: service)
        login.setEnabled(true)
        XCTAssertFalse(login.enabled); XCTAssertFalse(login.errorMessage.isEmpty)
        service.fail = false; login.setEnabled(true)
        XCTAssertTrue(login.enabled); XCTAssertTrue(login.errorMessage.isEmpty)
    }
    func testFailedRemovalKeepsActualEnabledState() {
        let service = FakeLoginItem(); service.status = .enabled; service.fail = true
        let login = LoginLaunch(service: service)
        login.setEnabled(false)
        XCTAssertTrue(login.enabled); XCTAssertFalse(login.errorMessage.isEmpty)
    }
    func testLoginLaunchHidesTheWindowButNormalLaunchDoesNot() {
        XCTAssertFalse(LoginLaunch.isLoginLaunch(nil))
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertFalse(LoginLaunch.isLoginLaunch(event))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        XCTAssertTrue(LoginLaunch.isLoginLaunch(event))
    }
}
