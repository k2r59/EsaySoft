import AppKit
import ApplicationServices

/// Freeze the destination when opening the shelf. App activation during browsing
/// must not change it, and a later manual app switch cancels automatic pasting.
struct PasteDestinationPolicy {
    static func resolve(own: pid_t, focused: pid_t?, frontmost: pid_t?, lastExternal: pid_t?) -> pid_t? {
        [focused, frontmost, lastExternal].compactMap { $0 }.first { $0 > 0 && $0 != own }
    }
    static func canActivate(own: pid_t, destination: pid_t, frontmost: pid_t?) -> Bool {
        guard destination > 0, destination != own, let frontmost else { return false }
        return frontmost == own || frontmost == destination
    }
}

@MainActor final class PasteDestinationTracker {
    private let own = ProcessInfo.processInfo.processIdentifier
    private(set) var lastExternal: NSRunningApplication?
    private var observer: NSObjectProtocol?
    init() {
        remember(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated { self?.remember(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }
        }
    }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    private func remember(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != own, !app.isTerminated,
              !["com.apple.dock", "com.apple.SystemUIServer", "com.apple.controlcenter"].contains(app.bundleIdentifier ?? "") else { return }
        lastExternal = app
    }
    func capture() -> NSRunningApplication? {
        var focusedPID: pid_t?
        // AX reflects the focused app even when NSWorkspace still reports the
        // previous app during a global-shortcut activation transition.
        if AXIsProcessTrusted() {
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.08)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value) == .success,
               let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                var pid: pid_t = 0
                if AXUIElementGetPid(value as! AXUIElement, &pid) == .success { focusedPID = pid }
            }
        }
        guard let pid = PasteDestinationPolicy.resolve(own: own, focused: focusedPID,
            frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            lastExternal: lastExternal?.isTerminated == false ? lastExternal?.processIdentifier : nil) else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }
}
