import AppKit
import SwiftUI
import AVFoundation

struct RecordingDevice: Identifiable {
    let id: String
    let name: String
    static var cameras: [RecordingDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices.map { .init(id: $0.uniqueID, name: $0.localizedName) }
    }
    static var microphones: [RecordingDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices.map { .init(id: $0.uniqueID, name: $0.localizedName) }
    }
}
enum CameraCorner: String, CaseIterable, Identifiable {
    case bottomRight, bottomLeft, topRight, topLeft
    var id: String { rawValue }
    var title: String { switch self { case .bottomRight: "En bas à droite"; case .bottomLeft: "En bas à gauche"; case .topRight: "En haut à droite"; case .topLeft: "En haut à gauche" } }
}
enum RecordingOverlayGeometry {
    static func cameraFrame(in area: CGRect, corner: CameraCorner) -> CGRect {
        let margin = min(16, min(area.width, area.height) * 0.05)
        let width = min(224, area.width * 0.30, (area.height - margin * 2) * 4 / 3)
        let height = width * 3 / 4
        let right = corner == .bottomRight || corner == .topRight
        let top = corner == .topRight || corner == .topLeft
        return CGRect(x: right ? area.maxX - margin - width : area.minX + margin,
                      y: top ? area.maxY - margin - height : area.minY + margin, width: width, height: height)
    }
    static func toolbarFrame(area: CGRect, screen: CGRect, size: CGSize) -> CGRect {
        let width = min(size.width, screen.width - 16)
        let y: CGFloat
        if area.minY - size.height - 12 >= screen.minY { y = area.minY - size.height - 12 }
        else if area.maxY + size.height + 12 <= screen.maxY { y = area.maxY + 12 }
        else { y = screen.minY + 18 }
        return CGRect(x: min(max(screen.minX + 8, area.midX - width / 2), screen.maxX - width - 8), y: y, width: width, height: size.height)
    }
}

final class WebcamSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "EasyPaste.webcam", qos: .userInitiated)
    func start(deviceID: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let device = deviceID.isEmpty ? AVCaptureDevice.default(for: .video) : AVCaptureDevice(uniqueID: deviceID)
                    guard let device else { throw CaptureFailure.message("Aucune webcam disponible. Branche-la ou désactive la webcam.") }
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    if self.session.canSetSessionPreset(.vga640x480) { self.session.sessionPreset = .vga640x480 }
                    guard self.session.canAddInput(input) else { self.session.commitConfiguration(); throw CaptureFailure.message("La webcam est occupée ou indisponible.") }
                    self.session.addInput(input); self.session.commitConfiguration()
                    self.session.startRunning()
                    guard self.session.isRunning else { throw CaptureFailure.message("La webcam n’a pas démarré.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() }; for input in self.session.inputs { self.session.removeInput(input) } } }
}
private final class WebcamPreview: NSView {
    let preview: AVCaptureVideoPreviewLayer
    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 22; layer?.masksToBounds = true
        preview.videoGravity = .resizeAspectFill; layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); preview.frame = bounds; CATransaction.commit() }
}
@MainActor final class RecordingHUDModel: ObservableObject {
    @Published var title = "Préparation…"
    @Published var elapsed = "0:00"
    @Published var stopping = false
    @Published var countdown: Int?
    var microphone = false
    var webcam = false
}
private struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel
    let stop: () -> Void
    let placeCamera: (CameraCorner) -> Void
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "line.3.horizontal").font(.system(size: 13)).foregroundStyle(Theme.muted).help("Déplacer les commandes")
            Circle().fill(model.stopping ? Theme.muted : .red).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title).font(.system(size: 12, weight: .semibold))
                Text(model.countdown.map { "Début dans \($0)…" } ?? model.elapsed).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
            }.frame(width: 140, alignment: .leading)
            Image(systemName: model.microphone ? "mic.fill" : "mic.slash").foregroundStyle(model.microphone ? Theme.mint : Theme.muted).help(model.microphone ? "Microphone enregistré" : "Microphone désactivé")
            if model.webcam {
                Menu { ForEach(CameraCorner.allCases) { corner in Button(corner.title) { placeCamera(corner) } } } label: {
                    Image(systemName: "video.fill").foregroundStyle(Theme.mint).frame(width: 28, height: 28).contentShape(Rectangle())
                }.menuStyle(.borderlessButton).fixedSize().help("Position de la webcam")
            }
            Spacer(minLength: 0)
            Button(action: stop) {
                HStack(spacing: 7) {
                    if model.stopping { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.countdown == nil ? "stop.fill" : "xmark") }
                    Text(model.stopping ? "Enregistrement…" : model.countdown == nil ? "Arrêter" : "Annuler")
                }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).frame(height: 36)
                .foregroundStyle(.white).background(model.stopping ? Color.gray : Color(red: 0.80, green: 0.20, blue: 0.24), in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
            }.buttonStyle(FullAreaButtonStyle()).disabled(model.stopping).help("Arrêter et conserver la vidéo · ⌃⌥⌘S")
        }.padding(.horizontal, 16).frame(height: 68).background(Theme.panel).foregroundStyle(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.14)))
        .preferredColorScheme(.dark)
    }
}
@MainActor final class RecordingOverlay {
    let model = RecordingHUDModel()
    private var border: NSPanel?
    private var toolbar: NSPanel?
    private var camera: NSPanel?
    private var session: WebcamSession?
    private var area = CGRect.zero
    private var cameraErrorObserver: NSObjectProtocol?
    var cameraWindowID: CGWindowID? { camera.map { CGWindowID($0.windowNumber) } }
    var onCameraFailure: (() -> Void)?
    func show(area: CGRect, options: RecordingOptions, stop: @escaping () -> Void) async throws {
        self.area = area; model.microphone = options.microphone; model.webcam = options.webcam
        model.stopping = false; model.countdown = 3; model.title = "Prêt à enregistrer"
        let border = makePanel(frame: area.insetBy(dx: -3, dy: -3)); border.ignoresMouseEvents = true
        border.contentView = NSHostingView(rootView: RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.mint, lineWidth: 3))
        border.hasShadow = false; border.orderFrontRegardless(); self.border = border
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: area.midX, y: area.midY)) } ?? NSScreen.main
        let frame = RecordingOverlayGeometry.toolbarFrame(area: area, screen: screen?.visibleFrame ?? area, size: CGSize(width: options.webcam ? 470 : 430, height: 68))
        let toolbar = makePanel(frame: frame); toolbar.isMovableByWindowBackground = true
        toolbar.contentView = NSHostingView(rootView: RecordingHUDView(model: model, stop: stop, placeCamera: { [weak self] corner in self?.placeCamera(corner) }))
        toolbar.orderFrontRegardless(); self.toolbar = toolbar
        if options.webcam {
            let session = WebcamSession(); self.session = session
            try await session.start(deviceID: options.cameraID)
            try Task.checkCancellation()
            let camera = makePanel(frame: RecordingOverlayGeometry.cameraFrame(in: area, corner: .bottomRight))
            camera.level = .floating; camera.ignoresMouseEvents = true
            camera.contentView = WebcamPreview(session: session.session); camera.orderFrontRegardless(); self.camera = camera
            cameraErrorObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session.session, queue: .main) { [weak self] _ in Task { @MainActor in self?.onCameraFailure?() } }
        }
    }
    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .screenSaver
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
    private func placeCamera(_ corner: CameraCorner) { camera?.setFrame(RecordingOverlayGeometry.cameraFrame(in: area, corner: corner), display: true) }
    func recording() { model.countdown = nil; model.title = "Enregistrement en cours" }
    func stopping() { model.countdown = nil; model.stopping = true; model.title = "Vidéo en préparation"; camera?.orderOut(nil); session?.stop() }
    func close() {
        if let cameraErrorObserver { NotificationCenter.default.removeObserver(cameraErrorObserver) }; cameraErrorObserver = nil
        [border, toolbar, camera].forEach { $0?.orderOut(nil) }; border = nil; toolbar = nil; camera = nil
        session?.stop(); session = nil
    }
}
