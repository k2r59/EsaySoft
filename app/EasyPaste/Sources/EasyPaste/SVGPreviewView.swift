import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct SVGPreviewView: View {
    let document: SVGDocument
    @ObservedObject var history: History
    var render: @Sendable (SVGDocument) async throws -> Data = { try await SVGRenderer.render($0) }
    @State private var png: Data?
    @State private var image: NSImage?
    @State private var error = ""
    @State private var background = 0
    @State private var copied = false
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(Int(document.width)) × \(Int(document.height)) · SVG statique").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Spacer()
                Picker("Fond", selection: $background) {
                    Text("Damier").tag(0); Text("Clair").tag(1); Text("Sombre").tag(2)
                }.labelsHidden().frame(width: 105).accessibilityLabel("Fond de l’aperçu SVG")
            }
            GeometryReader { geometry in
                ZStack {
                    if background == 0 { Checkerboard() } else { (background == 1 ? Color.white : Color(white: 0.12)) }
                    if let image { Image(nsImage: image).resizable().scaledToFit().padding(24).frame(width: geometry.size.width, height: geometry.size.height) }
                    else if error.isEmpty { ProgressView("Rendu SVG…").padding(14).background(Theme.raised, in: RoundedRectangle(cornerRadius: 10)) }
                    else { Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning).padding(20).background(Theme.panel) }
                }.clipShape(RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text("PNG sans perte · jusqu’à 2 048 px").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Exporter le PNG…") { exportPNG() }.buttonStyle(PasteButtonStyle()).disabled(png == nil)
                Button(copied ? "PNG copié" : "Copier le PNG") { if let png { copied = history.copyPNG(png) } }
                    .buttonStyle(PasteButtonStyle(primary: true)).disabled(png == nil)
            }
        }.padding(14).task(id: document.canonical) {
            png = nil; image = nil; error = ""; copied = false
            do {
                let data = try await render(document); try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) as String? == UTType.png.identifier,
                      let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw TextIssue(message: "PNG indisponible.") }
                let decoded = NSImage(cgImage: cg, size: .zero)
                png = data; image = decoded
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func exportPNG() {
        guard let png else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Image.png"
        panel.allowedContentTypes = [.png]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do { try await Task.detached { try png.write(to: url, options: .atomic) }.value; history.report("PNG enregistré.") }
                catch { history.report(error.localizedDescription) }
            }
        }
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.88)))
            let cell: CGFloat = 14
            for y in 0...Int(size.height/cell) {
                for x in 0...Int(size.width/cell) where (x+y) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(x)*cell, y: CGFloat(y)*cell, width: cell, height: cell)), with: .color(Color(white: 0.77)))
                }
            }
        }.accessibilityHidden(true)
    }
}

enum SVGFile {
    static func isSVG(_ path: String) -> Bool { ["svg", "svgz"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) }
    static func read(_ url: URL) throws -> String {
        guard url.pathExtension.lowercased() != "svgz" else { throw TextIssue(message: "Décompresse ce SVGZ en SVG pour l’aperçu.") }
        let properties = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard properties.isRegularFile == true, let size = properties.fileSize, size <= SVGDocument.inputLimit else { throw TextIssue(message: "SVG limité à 512 Ko.") }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let data = try file.read(upToCount: SVGDocument.inputLimit + 1) ?? Data()
        guard data.count <= SVGDocument.inputLimit, let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw TextIssue(message: "Encodage SVG non pris en charge.") }
        return source
    }
}

/// SVG files never reach Quick Look. File references remain original references;
/// the controlled preview offers a separate PNG for transfer to other readers.
struct SVGFilePreview: View {
    let url: URL
    @ObservedObject var history: History
    @State private var document: SVGDocument?
    @State private var source = ""
    @State private var error = ""
    @State private var showSource = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Afficher le source", isOn: $showSource).toggleStyle(.button).buttonStyle(PasteButtonStyle())
            if showSource { ScrollView([.horizontal, .vertical]) { Text(StructuredText.prefix(source, bytes: StructuredText.displayLimit)).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(12) } }
            else if let document { SVGPreviewView(document: document, history: history) }
            else if !error.isEmpty { Text(error).font(.system(size: 12)).foregroundStyle(Theme.warning).padding(16) }
            else { ProgressView("Vérification du SVG…") }
        }.frame(height: 390).task(id: url) {
            source = ""; document = nil; error = ""
            do {
                let raw = try await Task.detached { try SVGFile.read(url) }.value
                try Task.checkCancellation(); source = raw
                let parsed = try await Task.detached { try SVGDocument.parse(raw) }.value
                try Task.checkCancellation(); document = parsed
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
