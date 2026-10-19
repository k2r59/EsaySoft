import SwiftUI
import AVKit
import AppKit
import Quartz

struct HistorySheets: ViewModifier {
    @ObservedObject var history: History
    var host = "library"
    private func item(_ key: ReferenceWritableKeyPath<History, Clip?>) -> Binding<Clip?> {
        Binding(get: { history.surface == host ? history[keyPath: key] : nil }, set: { if history.surface == host { history[keyPath: key] = $0 } })
    }
    private func flag(_ key: ReferenceWritableKeyPath<History, Bool>) -> Binding<Bool> {
        Binding(get: { history.surface == host && history[keyPath: key] }, set: { if history.surface == host { history[keyPath: key] = $0 } })
    }
    func body(content: Content) -> some View {
        content
            .sheet(item: item(\.editing)) { clip in EditorView(history: history, clip: clip) }
            .sheet(isPresented: flag(\.newSnippet)) { EditorView(history: history, clip: nil) }
            .sheet(isPresented: flag(\.showNewBoard)) { NewBoardView(history: history) }
    }
}
@MainActor final class RichTextModel: ObservableObject {
    let textView = NSTextView()
    @Published var ready = false
    init() {
        textView.isRichText = true; textView.allowsUndo = true; textView.isEditable = true
        textView.font = .systemFont(ofSize: 15); textView.textColor = .black
        textView.backgroundColor = .white; textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.autoresizingMask = [.width]; textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false; textView.textContainer?.widthTracksTextView = true
    }
    func load(_ clip: Clip?) {
        if let rtf = clip?.payload.representations.flatMap({ $0 }).first(where: { $0.type == NSPasteboard.PasteboardType.rtf.rawValue })?.data, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attributed)
        } else { textView.string = clip?.text ?? "" }
        ready = true
    }
    func trait(_ trait: NSFontTraitMask) {
        let range = textView.selectedRange()
        let font = range.length > 0 ? textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont : textView.typingAttributes[.font] as? NSFont
        let current = font ?? .systemFont(ofSize: 15)
        let mask: NSFontTraitMask = NSFontManager.shared.traits(of: current).contains(trait) ? (trait == .boldFontMask ? .unboldFontMask : .unitalicFontMask) : trait
        if range.length == 0 { var attrs = textView.typingAttributes; attrs[.font] = NSFontManager.shared.convert(current, toHaveTrait: mask); textView.typingAttributes = attrs }
        else if let storage = textView.textStorage {
            let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            replacement.enumerateAttribute(.font, in: NSRange(location: 0, length: replacement.length)) { value, r, _ in replacement.addAttribute(.font, value: NSFontManager.shared.convert(value as? NSFont ?? current, toHaveTrait: mask), range: r) }
            replace(range, with: replacement)
        }
        textView.window?.makeFirstResponder(textView)
    }
    func toggle(_ key: NSAttributedString.Key) {
        let range = textView.selectedRange()
        if range.length == 0 { var attrs = textView.typingAttributes; attrs[key] = (attrs[key] as? Int ?? 0) == 0 ? 1 : 0; textView.typingAttributes = attrs }
        else if let storage = textView.textStorage {
            let active = (storage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
            let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
            replacement.addAttribute(key, value: active ? 0 : 1, range: NSRange(location: 0, length: replacement.length)); replace(range, with: replacement)
        }
        textView.window?.makeFirstResponder(textView)
    }
    private func replace(_ range: NSRange, with value: NSAttributedString) {
        if textView.shouldChangeText(in: range, replacementString: value.string) { textView.textStorage?.replaceCharacters(in: range, with: value); textView.didChangeText(); textView.setSelectedRange(range) }
    }
    var rtf: Data? { textView.rtf(from: NSRange(location: 0, length: (textView.string as NSString).length)) }
}
final class WrappingScrollView: NSScrollView {
    override func tile() {
        super.tile()
        guard let text = documentView as? NSTextView, contentSize.width > 0 else { return }
        text.minSize = NSSize(width: 0, height: contentSize.height)
        text.maxSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        if abs(text.frame.width - contentSize.width) > 0.5 { text.setFrameSize(NSSize(width: contentSize.width, height: max(text.frame.height, contentSize.height))) }
        text.textContainer?.containerSize = NSSize(width: max(1, contentSize.width - text.textContainerInset.width * 2), height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.lineBreakMode = .byWordWrapping
    }
}
struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var model: RichTextModel
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WrappingScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .noBorder
        scroll.documentView = model.textView
        model.textView.frame = NSRect(x: 0, y: 0, width: 580, height: 350)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { view.tile() }
}
struct EditorView: View {
    @ObservedObject var history: History
    let clip: Clip?
    @StateObject private var model = RichTextModel()
    @State private var title = ""
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text(clip == nil ? "Nouveau texte" : "Modifier le texte").font(.system(size: 23, weight: .semibold)); Spacer(); Button("Annuler") { dismiss() }.buttonStyle(PasteButtonStyle()) }
            TextField("Titre (facultatif)", text: $title).textFieldStyle(.plain).font(.system(size: 16, weight: .medium)).padding(12).background(Theme.raised, in: RoundedRectangle(cornerRadius: 9)).accessibilityLabel("Titre du texte")
            HStack(spacing: 6) {
                format("bold", "Gras") { model.trait(.boldFontMask) }
                format("italic", "Italique") { model.trait(.italicFontMask) }
                format("underline", "Souligner") { model.toggle(.underlineStyle) }
                format("strikethrough", "Barrer") { model.toggle(.strikethroughStyle) }
                Spacer()
            }
            if model.ready { RichTextEditor(model: model).frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 12)) }
            else { ProgressView("Ouverture du texte…").frame(height: 310).frame(maxWidth: .infinity) }
            HStack { Text(error).font(.system(size: 11)).foregroundStyle(.orange); Spacer(); Button("Enregistrer") {
                let text = model.textView.string
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Saisis un texte avant d’enregistrer."; return }
                guard text.utf8.count + (model.rtf?.count ?? 0) <= ClipboardReader.limit else { error = "Ce texte dépasse la limite de 20 Mo."; return }
                let name = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(text.prefix(90)) : title
                if let clip { history.edit(clip.id, title: name, text: text, rtf: model.rtf) } else { history.makeSnippet(name, text: text, rtf: model.rtf) }
                dismiss()
            }.buttonStyle(PasteButtonStyle(primary: true)).disabled(!model.ready).keyboardShortcut("s", modifiers: .command) }
        }.padding(26).frame(width: 640).background(Theme.bg).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
        .task { title = clip?.title ?? ""; do { if let clip { model.load(try await history.fullClip(clip)) } else { model.load(nil) } } catch { self.error = error.localizedDescription } }
    }
    private func format(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).frame(width: 25, height: 25) }.buttonStyle(PasteButtonStyle()).help(label).accessibilityLabel(label) }
}
struct NewBoardView: View {
    @ObservedObject var history: History
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Nouvelle collection").font(.system(size: 25, weight: .semibold))
            Text("Ses éléments sont conservés sans limite de durée.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            TextField("Nom de la collection", text: $name).textFieldStyle(.roundedBorder).onSubmit { save() }.accessibilityLabel("Nom de la collection")
            HStack { Button("Annuler") { dismiss() }.buttonStyle(PasteButtonStyle()); Spacer(); Button("Créer la collection") { save() }.buttonStyle(PasteButtonStyle(primary: true)).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(28).frame(width: 400).background(Theme.bg).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
    }
    private func save() { guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }; history.addBoard(name); dismiss() }
}
struct FilePreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> QLPreviewView { let view = QLPreviewView(frame: .zero, style: .normal)!; view.previewItem = url as NSURL; view.autostarts = false; return view }
    func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
}
/// Use the AppKit player directly: the SwiftUI VideoPlayer overlay crashes while
/// initializing its generic metadata on some macOS/SDK combinations.
struct NativeVideoPreview: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.allowsVideoFrameAnalysis = false
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause(); view.player = nil
    }
}

@MainActor final class VideoPlayback: ObservableObject {
    let player: AVPlayer
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var playing = false
    @Published var scrubbing = false
    private var resumeAfterScrubbing = false
    private var observer: Any?
    private var endObserver: NSObjectProtocol?
    private var durationTask: Task<Void, Never>?
    init(player: AVPlayer) {
        self.player = player
        let asset = player.currentItem?.asset
        durationTask = Task { [weak self] in
            guard let asset, let duration = try? await asset.load(.duration), !Task.isCancelled, duration.seconds.isFinite else { return }
            self?.duration = max(0, duration.seconds)
        }
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.scrubbing, time.seconds.isFinite { self.position = max(0, time.seconds) }
                if let seconds = self.player.currentItem?.duration.seconds, seconds.isFinite { self.duration = max(0, seconds) }
                if !self.scrubbing { self.playing = self.player.rate > 0 }
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playing = false }
        }
    }
    deinit {
        durationTask?.cancel()
        if let observer { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }
    func toggle() {
        guard !scrubbing else { return }
        if playing { player.pause(); playing = false }
        else {
            if duration > 0, position >= duration - 0.05 { player.seek(to: .zero); position = 0 }
            player.play(); playing = true
        }
    }
    func scrub(_ active: Bool) {
        if active { resumeAfterScrubbing = playing; scrubbing = true; player.pause() }
        else {
            let target = CMTime(seconds: min(duration, max(0, position)), preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor in
                    guard let self, finished else { return }
                    self.scrubbing = false
                    if self.resumeAfterScrubbing { self.player.play() }
                    self.playing = self.resumeAfterScrubbing
                }
            }
        }
    }
}

struct VideoPreview: View {
    @StateObject private var playback: VideoPlayback
    init(player: AVPlayer) { _playback = StateObject(wrappedValue: VideoPlayback(player: player)) }
    var body: some View {
        VStack(spacing: 12) {
            NativeVideoPreview(player: playback.player).frame(height: 330)
            HStack(spacing: 14) {
                Button { playback.toggle() } label: {
                    Label(playback.playing ? "Pause" : "Lire", systemImage: playback.playing ? "pause.fill" : "play.fill").frame(width: 70)
                }.buttonStyle(PasteButtonStyle(primary: true)).keyboardShortcut(.space, modifiers: []).disabled(playback.scrubbing)
                Text(clock(playback.position)).monospacedDigit().frame(width: 42)
                Slider(value: $playback.position, in: 0...max(0.01, playback.duration), onEditingChanged: playback.scrub)
                    .tint(Theme.mint).disabled(playback.duration <= 0).accessibilityLabel("Position de lecture")
                Text(clock(playback.duration)).monospacedDigit().frame(width: 42)
            }.font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }
    private func clock(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
struct PreviewView: View {
    @ObservedObject var history: History
    let clip: Clip
    let close: () -> Void
    @State private var full: Clip?
    @State private var player: AVPlayer?
    @State private var videoWarning = ""
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 5) { eyebrow("APERÇU"); Text(clip.title).font(.system(size: 18, weight: .semibold)).lineLimit(2) }; Spacer(); Button("Fermer", action: close).buttonStyle(PasteButtonStyle()).keyboardShortcut(.cancelAction) }
            if let full {
                if !videoWarning.isEmpty { Label(videoWarning, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                if full.kind == .image, let data = full.imageData { ImagePreview(data: data) }
                else if full.kind == .video, let player { VideoPreview(player: player) }
                else if full.kind == .file, let path = full.text.split(separator: "\n").first { FilePreview(url: URL(fileURLWithPath: String(path))).frame(height: 350) }
                else { ScrollView { Text(full.text).textSelection(.enabled).font(.system(size: 14)).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading).padding(20) }.frame(height: 300).background(Theme.panel, in: RoundedRectangle(cornerRadius: 12)) }
                if !full.ocr.isEmpty { ScrollView { Text(full.ocr).textSelection(.enabled).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 85) }
                HStack { Text("\(full.source) · \(full.date.formatted(.dateTime.locale(Locale(identifier: "fr_FR")).day().month().hour().minute()))").font(.system(size: 10)).foregroundStyle(Theme.muted); Spacer(); if full.kind == .link || full.kind == .file { Button("Ouvrir") { openClip(full) }.buttonStyle(PasteButtonStyle()) }; if full.kind == .video { Button("Enregistrer…") { history.exportVideo(full) }.buttonStyle(PasteButtonStyle()) }; if !full.ocr.isEmpty { Button("Copier le texte") { Task { _ = await history.copy([full], plain: true) } }.buttonStyle(PasteButtonStyle()) }; Button("Copier") { Task { _ = await history.copy([full]) } }.buttonStyle(PasteButtonStyle(primary: true)) }
            } else if error.isEmpty { ProgressView("Chargement…").frame(maxWidth: .infinity).frame(height: 250) }
            else { Text(error).foregroundStyle(.orange) }
        }.padding(25).frame(width: 650).background(Theme.bg).foregroundStyle(Theme.ink).preferredColorScheme(.dark)
        .task {
            do {
                let value = try await history.fullClip(clip)
                try Task.checkCancellation()
                if value.kind == .video {
                    let url = try await history.videoURL(value); guard !Task.isCancelled else { return }
                    let asset = AVURLAsset(url: url)
                    if let duration = try? await asset.load(.duration), let track = try? await asset.loadTracks(withMediaType: .video).first,
                       let range = try? await track.load(.timeRange), duration.seconds - range.end.seconds > 0.25 {
                        videoWarning = "Cette ancienne vidéo contient une piste image incomplète. Refais la capture avec la nouvelle version."
                    }
                    guard !Task.isCancelled else { return }; player = AVPlayer(url: url)
                }
                full = value
            } catch { self.error = error.localizedDescription }
        }.onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
    }
}

/// A centered panel keeps the player controls visible even when launched from
/// the quick bar at the bottom of the screen. The player is released on close.
@MainActor final class PreviewController: NSObject, NSWindowDelegate {
    private let history: History
    private var window: NSPanel?
    private var clipID: UUID?
    init(history: History) { self.history = history }
    func present(_ clip: Clip?) {
        guard let clip else { close(); return }
        if clipID == clip.id, let window { window.makeKeyAndOrderFront(nil); return }
        close()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame, height = min(620, visible.height - 80)
        let panel = NSPanel(contentRect: CGRect(x: visible.midX - 325, y: visible.midY - height / 2, width: 650, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Aperçu EasyPaste"; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.hidesOnDeactivate = false; panel.delegate = self; panel.backgroundColor = NSColor(Theme.bg)
        let content = ScrollView { PreviewView(history: history, clip: clip, close: { [weak self] in self?.history.previewing = nil }) }
            .frame(width: 650, height: height).background(Theme.bg).preferredColorScheme(.dark)
        panel.contentView = NSHostingView(rootView: content)
        window = panel; clipID = clip.id; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { history.previewing = nil; return false }
    private func close() { window?.orderOut(nil); window?.contentView = nil; window = nil; clipID = nil }
}
