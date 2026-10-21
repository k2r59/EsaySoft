import AppKit
import Carbon
import Combine
import ServiceManagement

@MainActor protocol LoginItemManaging {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

@MainActor struct SystemLoginItem: LoginItemManaging {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

@MainActor final class LoginLaunch: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage = ""
    private let service: any LoginItemManaging
    var enabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    init(service: (any LoginItemManaging)? = nil) {
        self.service = service ?? SystemLoginItem()
        refresh()
    }

    func refresh() { status = service.status }

    func setEnabled(_ value: Bool) {
        errorMessage = ""
        do {
            if value {
                if service.status == .requiresApproval { service.openSettings() }
                else if service.status != .enabled { try service.register() }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            errorMessage = "Ouverture au démarrage : \(error.localizedDescription)"
        }
        // macOS is the source of truth; never show an enabled switch after a refusal.
        refresh()
    }

    func openSettings() { service.openSettings() }

    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard event?.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
