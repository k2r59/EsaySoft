import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation

enum CaptureAction: Int, CaseIterable {
    case area, window, screen, text, video
    var title: String { switch self { case .area: "Capturer une zone"; case .window: "Capturer une fenêtre"; case .screen: "Capturer l’écran"; case .text: "Extraire le texte d’une zone"; case .video: "Enregistrer une vidéo…" } }
    var icon: String { switch self { case .area: "viewfinder"; case .window: "macwindow"; case .screen: "display"; case .text: "text.viewfinder"; case .video: "record.circle" } }
}
struct CaptureMenu: View {
    @ObservedObject var history: History
    var body: some View {
        Menu {
            ForEach(CaptureAction.allCases, id: \.self) { action in
                if action == .text || action == .video { Divider() }
                Button { history.capture?(action) } label: { Label(action.title, systemImage: action.icon) }.disabled(history.captureBusy || history.recording || history.annotating)
            }
            if history.recording { Divider(); Button("Arrêter l’enregistrement") { history.stopRecording?() } }
        } label: { Label(history.recording ? "Enregistrement" : history.captureBusy ? "Capture…" : "Capturer", systemImage: history.recording ? "record.circle.fill" : "viewfinder").font(.system(size: 12, weight: .semibold)).foregroundStyle(history.recording ? .red : Theme.mint).padding(.horizontal, 12).padding(.vertical, 9).background(Theme.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).contentShape(.interaction, Rectangle()) }
        .menuStyle(.borderlessButton).fixedSize().help("Capture d’écran, texte et vidéo")
    }
}
@MainActor final class CaptureController: NSObject, NSWindowDelegate {
    let history: History
    private let recorder = Recorder()
    private let recordingOverlay = RecordingOverlay()
    private var overlays: [NSWindow] = []
    private var panel: NSPanel?
    private var selectionContinuation: CheckedContinuation<CGRect?, Never>?
    private var task: Task<Void, Never>?
    private var ticker: Timer?
    private var started: Date?
    private var currentAction: CaptureAction?
    private var operation: UUID?
    var hideApp: (() -> Void)?
    var showResult: (() -> Void)?
    var statusChanged: ((String?) -> Void)?
    init(history: History) {
        self.history = history; super.init()
        recorder.onStart = { [weak self] in
            guard let self else { return }
            self.started = Date(); self.history.recording = true; self.history.captureBusy = false
            self.recordingOverlay.recording()
            self.updateStatus()
            self.ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatus(); self?.recorder.checkSize() } }
            self.ticker?.tolerance = 0.1
        }
        recorder.onStopping = { [weak self] in
            self?.history.captureBusy = true; self?.history.recording = false; self?.recordingOverlay.stopping(); self?.statusChanged?("Finalisation…")
        }
        recorder.onFinish = { [weak self] result in self?.finishedRecording(result) }
        recordingOverlay.onCameraFailure = { [weak self] in
            self?.stop(); self?.history.report("La webcam s’est interrompue. La vidéo en cours est conservée.")
        }
    }
    func run(_ action: CaptureAction) {
        guard !history.captureBusy, !history.samplingColor, !history.recording, !history.annotating, !history.loading, !history.fault else { return }
        let id = UUID(); operation = id; currentAction = action; history.captureBusy = true
        if !CGPreflightScreenCaptureAccess() { showPermission(action); return }
        if action == .video {
            present(RecordingSetupView(cancel: { [weak self] in self?.cancel() }, start: { [weak self] options in self?.beginVideo(options) }), title: "Enregistrer une vidéo")
        } else {
            task = Task { [weak self] in await self?.captureImage(action, id: id) }
        }
    }
    private func showPermission(_ action: CaptureAction) {
        present(VStack(alignment: .leading, spacing: 20) {
            Label("Autoriser la capture d’écran", systemImage: "lock.shield").font(.system(size: 20, weight: .semibold))
            Text("Active EasyPaste dans Confidentialité et sécurité → Enregistrement de l’écran et de l’audio système. Cette autorisation sert aussi aux captures d’image et à la lecture du texte.").fixedSize(horizontal: false, vertical: true).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Text("Si macOS demande de quitter l’app, rouvre EasyPaste depuis Applications.").fixedSize(horizontal: false, vertical: true).font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack { Button("Plus tard") { self.cancel() }.buttonStyle(PasteButtonStyle()); Spacer(); Button("Autoriser…") {
                _ = CGRequestScreenCaptureAccess()
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }.buttonStyle(PasteButtonStyle()); Button("Réessayer") { self.dismissPanel(); self.history.captureBusy = false; self.run(action) }.buttonStyle(PasteButtonStyle(primary: true)) }
        }.padding(28).frame(width: 490).background(Theme.bg).foregroundStyle(Theme.ink), title: "Autorisation EasyPaste")
    }
    private func present<V: View>(_ view: V, title: String) {
        dismissPanel()
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled,.closable], backing: .buffered, defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; panel.level = .floating; panel.delegate = self; panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: view); panel.center(); self.panel = panel
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func dismissPanel() { panel?.orderOut(nil); panel = nil }
    @discardableResult func revealActiveControls() -> Bool {
        if let panel { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return true }
        if recordingOverlay.revealControls() { return true }
        if let overlay = overlays.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? overlays.first {
            overlay.makeKeyAndOrderFront(nil); return true
        }
        return false
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { cancel(); return false }
    func cancel() {
        operation = nil; task?.cancel(); task = nil; dismissPanel(); finishSelection(nil); recordingOverlay.close()
        recorder.cancel(); ticker?.invalidate(); ticker = nil; started = nil
        history.captureBusy = false; history.recording = false; statusChanged?(nil); showResult?()
    }
    private func screenRect() -> CGRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return .zero }
        return Self.quartzRect(screen.frame)
    }
    static func quartzRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0)-rect.maxY, width: rect.width, height: rect.height)
    }
    private func select(windows: [SCWindow] = []) async -> CGRect? {
        await withCheckedContinuation { continuation in
            selectionContinuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            for screen in NSScreen.screens {
                let window = SelectionWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.backgroundColor = .clear; window.isOpaque = false; window.level = .screenSaver; window.isReleasedWhenClosed = false
                window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; window.acceptsMouseMovedEvents = true
                let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
                if !windows.isEmpty {
                    view.instruction = "Clique sur une fenêtre · Échap pour annuler"
                    view.windowFrames = windows.map { candidate in
                        let quartzScreen = Self.quartzRect(screen.frame)
                        return CGRect(x: candidate.frame.minX-screen.frame.minX, y: screen.frame.height-(candidate.frame.maxY-quartzScreen.minY), width: candidate.frame.width, height: candidate.frame.height)
                    }
                } else { view.instruction = currentAction == .text ? "Encadre le texte à copier · Échap pour annuler" : "Glisse pour sélectionner une zone · Échap pour annuler" }
                view.done = { [weak self] rect in
                    let result = rect.map { Self.quartzRect($0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)) }
                    self?.finishSelection(result)
                }
                window.contentView = view; overlays.append(window); window.orderFrontRegardless()
                if screen.frame.contains(NSEvent.mouseLocation) { window.makeKey(); window.makeFirstResponder(view) }
            }
        }
    }
    private func finishSelection(_ rect: CGRect?) {
        overlays.forEach { $0.orderOut(nil) }; overlays.removeAll()
        let continuation = selectionContinuation; selectionContinuation = nil; continuation?.resume(returning: rect)
    }
    private func captureImage(_ action: CaptureAction, id: UUID) async {
        let screen = screenRect(); hideApp?()
        defer { if operation == id { history.captureBusy = false; task = nil; operation = nil } }
        do {
            let image: CGImage
            if action == .window {
                let content = try await CaptureImage.content()
                let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? UInt32 }
                let byID = Dictionary(uniqueKeysWithValues: content.windows.map { ($0.windowID,$0) })
                let windows = order.compactMap { byID[$0] }.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 80 && $0.frame.height > 50 }
                guard !windows.isEmpty else { throw CaptureFailure.message("Aucune fenêtre disponible à capturer.") }
                guard let rect = await select(windows: windows), let window = windows.first(where: { $0.frame == rect }) else { if operation == id { showResult?() }; return }
                try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(140))
                image = try await CaptureImage.window(window)
            } else {
                let rect: CGRect
                if action == .screen { rect = screen }
                else { guard let selected = await select() else { if operation == id { showResult?() }; return }; rect = selected }
                try Task.checkCancellation(); try await Task.sleep(for: .milliseconds(140))
                image = try await CaptureImage.region(rect)
            }
            let data = try await Task.detached(priority: .userInitiated) { try CaptureImage.png(image) }.value
            try Task.checkCancellation()
            let clip: Clip
            if action == .text {
                let text = try await Task.detached(priority: .userInitiated) { try ImageText.recognize(data) }.value
                try Task.checkCancellation(); guard operation == id else { return }
                clip = try await history.saveOCR(text)
            } else { clip = try await history.saveImage(data) }
            history.sounds.play(.capture)
            let copied = await history.copy([clip], sound: nil); showResult?()
            history.report(copied ? (action == .text ? "Texte copié · ⌘V pour coller" : "Capture copiée · ⌘V pour coller") : "Capture enregistrée dans l’historique.")
        } catch is CancellationError { if operation == id { showResult?() } }
        catch { if operation == id { showResult?(); history.report(error.localizedDescription) } }
    }
    private func beginVideo(_ options: RecordingOptions) {
        guard let id = operation else { return }
        dismissPanel()
        let screen = screenRect()
        task = Task {
            do {
                if options.microphone {
                    let authorized = AVCaptureDevice.authorizationStatus(for: .audio)
                    let granted = authorized == .authorized ? true : authorized == .notDetermined ? await AVCaptureDevice.requestAccess(for: .audio) : false
                    guard granted else { throw CaptureFailure.message("Le microphone n’est pas autorisé. Active-le dans Confidentialité et sécurité → Microphone, ou désactive cette option.") }
                }
                if options.webcam {
                    let authorized = AVCaptureDevice.authorizationStatus(for: .video)
                    let granted = authorized == .authorized ? true : authorized == .notDetermined ? await AVCaptureDevice.requestAccess(for: .video) : false
                    guard granted else { throw CaptureFailure.message("La webcam n’est pas autorisée. Active-la dans Confidentialité et sécurité → Appareil photo, ou désactive cette option.") }
                }
                try Task.checkCancellation(); guard operation == id else { return }
                hideApp?()
                let area: CGRect
                if options.area { guard let rect = await select() else { if operation == id { history.captureBusy = false; operation = nil; showResult?() }; return }; area = rect }
                else { area = screen }
                if options.webcam && (area.width < 240 || area.height < 180) { throw CaptureFailure.message("Sélectionne une zone d’au moins 240 × 180 points pour inclure la webcam.") }
                try await recordingOverlay.show(area: Self.quartzRect(area), options: options, stop: { [weak self = self] in
                    guard let self else { return }; if self.recorder.state == .recording { self.stop() } else { self.cancel() }
                })
                for count in (1...3).reversed() {
                    try Task.checkCancellation(); recordingOverlay.model.countdown = count
                    try await Task.sleep(for: .seconds(1))
                }
                recordingOverlay.model.countdown = nil; recordingOverlay.model.title = "Démarrage…"
                try Task.checkCancellation()
                let content = try await CaptureImage.content()
                guard let display = content.displays.first(where: { $0.frame.contains(area) }) else { throw CaptureFailure.message("La zone vidéo doit tenir sur un seul écran.") }
                try await recorder.start(display: display, area: area, content: content, options: options, cameraWindow: recordingOverlay.cameraWindowID)
                task = nil
            } catch is CancellationError { recordingOverlay.close(); if operation == id { dismissPanel(); history.captureBusy = false; operation = nil; showResult?() } }
            catch { recordingOverlay.close(); if operation == id { dismissPanel(); history.captureBusy = false; operation = nil; showResult?(); history.report(error.localizedDescription) } }
        }
    }
    func stop() { if recorder.state == .recording || recorder.state == .starting { recorder.stop() } }
    private func updateStatus() {
        guard let started, recorder.state == .recording else { return }
        let seconds = Int(Date().timeIntervalSince(started))
        let elapsed = String(format: "%d:%02d", seconds/60, seconds%60)
        recordingOverlay.model.elapsed = elapsed; statusChanged?(elapsed)
    }
    private func finishedRecording(_ result: Result<URL, Error>) {
        ticker?.invalidate(); ticker = nil; started = nil; history.recording = false; history.captureBusy = true; statusChanged?("Enregistrement…"); recordingOverlay.stopping()
        Task {
            defer { history.captureBusy = false; operation = nil; statusChanged?(nil); recordingOverlay.close() }
            do {
                let url = try result.get()
                let clip = try await history.saveVideo(url)
                try? FileManager.default.removeItem(at: url)
                let copied = await history.copy([clip]); showResult?()
                history.report(copied ? "Vidéo copiée" : "Vidéo enregistrée dans l’historique.")
            } catch {
                showResult?(); history.report("Vidéo : " + error.localizedDescription)
                if let url = try? result.get(), FileManager.default.fileExists(atPath: url.path) {
                    let alert = NSAlert()
                    alert.messageText = "La vidéo est conservée sur ton Mac."
                    alert.informativeText = "L’ajout à l’historique a échoué : " + error.localizedDescription + "\nTu peux retrouver le fichier dans le Finder."
                    alert.addButton(withTitle: "Afficher le fichier"); alert.addButton(withTitle: "Plus tard")
                    if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        }
    }
}
