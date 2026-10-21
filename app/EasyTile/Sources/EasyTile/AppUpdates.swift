import AppKit
import Combine
import Sparkle
import SwiftUI

/// No network activity until start() is called by the normal application.
/// Unit tests and placement diagnostics never start the updater.
@MainActor final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var available = false
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var automaticInstall = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var message = ""
    @Published private(set) var waitingToInstall = false
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    var busy: () -> Bool = { false }
    private var deferredInstall: (() -> Void)?

    static func isBusy(editor: Bool, dragging: Bool, placement: Bool, palette: Bool) -> Bool {
        editor || dragging || placement || palette
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
            observations = [
                controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
                    Task { @MainActor in self?.canCheck = change.newValue ?? false }
                },
                controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] _, change in
                    Task { @MainActor in self?.automaticChecks = change.newValue ?? false }
                },
                controller.updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { [weak self] _, change in
                    Task { @MainActor in self?.automaticInstall = change.newValue ?? false }
                },
                controller.updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, change in
                    Task { @MainActor in self?.lastCheck = change.newValue ?? nil }
                }
            ]
        } catch {
            message = "Les mises à jour n’ont pas pu démarrer. Réessaie après avoir relancé EasyTile."
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        guard available, let updater = controller?.updater else { return }
        if !enabled {
            updater.automaticallyDownloadsUpdates = false
            automaticInstall = false
        }
        updater.automaticallyChecksForUpdates = enabled
        automaticChecks = enabled
    }

    func setAutomaticInstall(_ enabled: Bool) {
        guard available, let updater = controller?.updater else { return }
        if enabled { setAutomaticChecks(true) }
        updater.automaticallyDownloadsUpdates = enabled
        automaticInstall = enabled
    }

    func check() {
        guard !busy() else { message = Self.busyMessage; return }
        guard canCheck else { return }
        message = ""
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    static let busyMessage = "Ferme l’éditeur ou la palette et termine le placement avant la mise à jour."

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if busy() {
            throw NSError(domain: "EasyTile.Updates", code: 1,
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
        message = "EasyTile \(item.displayVersionString) est disponible."
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        message = "EasyTile est à jour."
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        if error.domain == SUSparkleErrorDomain && error.code == SUError.noUpdateError.rawValue {
            message = "EasyTile est à jour."
        } else if error.domain == "EasyTile.Updates" {
            message = Self.busyMessage
        } else {
            message = "Vérification interrompue. Réessaie lorsque la connexion est disponible."
        }
    }
}
