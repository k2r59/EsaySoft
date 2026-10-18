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
            .sheet(item: item(\.previewing)) { clip in PreviewView(history: history, clip: clip) }
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
            HStack { VStack(alignment: .leading, spacing: 6) { eyebrow(clip == nil ? "NOUVEAU TEXTE" : "ÉDITION"); Text("Les bons mots, à ta façon.").font(.system(size: 23, weight: .semibold)) }; Spacer(); Button("Annuler") { dismiss() }.buttonStyle(PasteButtonStyle()) }
            TextField("Titre de ton texte", text: $title).textFieldStyle(.plain).font(.system(size: 16, weight: .medium)).padding(12).background(Theme.raised, in: RoundedRectangle(cornerRadius: 9))
            HStack(spacing: 6) {
                format("bold", "Gras") { model.trait(.boldFontMask) }
                format("italic", "Italique") { model.trait(.italicFontMask) }
                format("underline", "Souligner") { model.toggle(.underlineStyle) }
                format("strikethrough", "Barrer") { model.toggle(.strikethroughStyle) }
                Spacer(); Text("Le format est conservé au collage.").font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            if model.ready { RichTextEditor(model: model).frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 12)) }
            else { ProgressView("Ouverture du texte…").frame(height: 310).frame(maxWidth: .infinity) }
            HStack { Text(error).font(.system(size: 11)).foregroundStyle(.orange); Spacer(); Button("Enregistrer") {
                let text = model.textView.string
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Ajoute un peu de texte avant d’enregistrer."; return }
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
            eyebrow("UNE PLACE POUR TES IDÉES")
            Text("Nouvelle collection").font(.system(size: 25, weight: .semibold))
            Text("Les éléments d’une collection restent disponibles sans limite de durée.").font(.system(size: 12)).foregroundStyle(Theme.muted)
            TextField("Par exemple : Réponses utiles", text: $name).textFieldStyle(.roundedBorder).onSubmit { save() }
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
        view.controlsStyle = .inline
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
struct PreviewView: View {
    @ObservedObject var history: History
    let clip: Clip
    @State private var full: Clip?
    @State private var player: AVPlayer?
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 5) { eyebrow("APERÇU"); Text(clip.title).font(.system(size: 18, weight: .semibold)).lineLimit(2) }; Spacer(); Button("Fermer") { dismiss() }.buttonStyle(PasteButtonStyle()).keyboardShortcut(.cancelAction) }
            if let full {
                if full.kind == .image, let data = full.imageData { ImagePreview(data: data) }
                else if full.kind == .video, let player { NativeVideoPreview(player: player).frame(height: 350) }
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
                if value.kind == .video { let url = try await history.videoURL(value); guard !Task.isCancelled else { return }; player = AVPlayer(url: url) }
                full = value
            } catch { self.error = error.localizedDescription }
        }.onDisappear { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil }
    }
}
