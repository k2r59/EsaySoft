import AppKit
import Combine
import Sparkle
import SwiftUI

/// No network activity until start() is called by the normal application.
/// MCP, SVG helpers, unit tests and demonstrations never start the updater.
@MainActor final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var available = false
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var message = ""
    @Published private(set) var waitingToInstall = false
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    var busy: () -> Bool = { false }
    private var deferredInstall: (() -> Void)?

    static func isBusy(recording: Bool, capture: Bool, annotation: Bool, editor: Bool,
                       preview: Bool, sampling: Bool, sharing: Bool) -> Bool {
        recording || capture || annotation || editor || preview || sampling || sharing
    }

    func start() {
        guard controller == nil else { return }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            message = "Mises à jour indisponibles dans cette version de développement."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            available = true
            controller.updater.sendsSystemProfile = false
            // Checking is optional; downloading/installing always requires the user.
            controller.updater.automaticallyDownloadsUpdates = false
            observations = [
                controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                    Task { @MainActor in self?.canCheck = change.newValue ?? false }
                },
                controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                    Task { @MainActor in self?.automaticChecks = change.newValue ?? false }
                },
                controller.updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, change in
                    Task { @MainActor in self?.lastCheck = change.newValue ?? nil }
                }
            ]
        } catch {
            message = "Les mises à jour n’ont pas pu démarrer. Réessaie après avoir relancé EasyPaste."
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard available, let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = enabled
        automaticChecks = enabled
    }

    func check() {
        guard !busy() else { message = Self.busyMessage; return }
        guard canCheck else { return }
        message = ""
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    static let busyMessage = "Termine la capture, l’édition ou le partage en cours avant la mise à jour."

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if busy() {
            throw NSError(domain: "EasyPaste.Updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: Self.busyMessage])
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeIfBusy(installHandler)
    }

    @discardableResult func postponeIfBusy(_ install: @escaping () -> Void) -> Bool {
        guard busy() else { return false }
        deferredInstall = install
        waitingToInstall = true
        message = Self.busyMessage
        return true
    }

    func installWhenReady() {
        guard !busy(), let install = deferredInstall else {
            if waitingToInstall { message = Self.busyMessage }
            return
        }
        deferredInstall = nil
        waitingToInstall = false
        message = ""
        install()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        message = "EasyPaste \(item.displayVersionString) est disponible."
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        message = "EasyPaste est à jour."
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
            message = "EasyPaste est à jour."
        } else if error.domain == "EasyPaste.Updates" {
            message = Self.busyMessage
        } else {
            message = "Vérification interrompue. Réessaie lorsque la connexion est disponible."
        }
    }
}

struct UpdateSettings: View {
    @ObservedObject var updates: AppUpdates
    var busy: Bool
    var body: some View {
        PreferenceToggle("Vérifier automatiquement", isOn: Binding(
            get: { updates.automaticChecks }, set: updates.setAutomaticChecks
        )).disabled(!updates.available)
        PreferenceRow("EasyPaste \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
            Button(updates.waitingToInstall ? "Installer et relancer" : "Rechercher une mise à jour…") {
                if updates.waitingToInstall { updates.installWhenReady() } else { updates.check() }
            }.buttonStyle(PasteButtonStyle())
                .disabled(busy || (!updates.waitingToInstall && !updates.canCheck))
        }
        Text(busy ? AppUpdates.busyMessage :
                (!updates.message.isEmpty ? updates.message :
                    "L’installation reste à ta main. Historique et réglages sont conservés."))
            .font(.system(size: 11)).foregroundStyle(Theme.muted)
        if let date = updates.lastCheck {
            Text("Dernière vérification : \(date.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }
}
