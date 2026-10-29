import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

extension MusicStore {
    func defaultArtwork(for playlist: Playlist) -> String? {
        guard let first = playlistTracks(playlist).first else { return nil }
        return first.artwork ?? downloaded(first)?.track.artwork
    }
    func chooseArtwork(for id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false; panel.prompt = "Choisir la pochette"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try setArtwork(for: id, from: url) }
        catch { showError("Impossible de lire cette image. Choisissez une image JPEG, PNG ou HEIC valide.") }
    }
    func setArtwork(for id: UUID, from url: URL) throws {
        guard let index = library.playlists.firstIndex(where: { $0.id == id }) else { return }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw MusicError.message("Image illisible")
        }
        let folder = storage.deletingLastPathComponent().appendingPathComponent("PlaylistArtwork", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(UUID().uuidString + ".png")
        try data.write(to: destination, options: .atomic)
        library.playlists[index].artworkPath = destination.path
        save()
    }
    func resetArtwork(for id: UUID) {
        guard let index = library.playlists.firstIndex(where: { $0.id == id }) else { return }
        library.playlists[index].artworkPath = nil; save()
    }
}

struct PlaylistArtwork: View {
    @EnvironmentObject var store: MusicStore
    let playlist: Playlist
    var size: CGFloat = 42
    @State private var customImage: NSImage?
    var body: some View {
        Group {
            if let customImage { Image(nsImage: customImage).resizable().scaledToFill() }
            else { Art(url: store.defaultArtwork(for: playlist), size: size) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size > 100 ? 8 : 5))
            .task(id: playlist.artworkPath) {
                customImage = playlist.artworkPath.flatMap { NSImage(contentsOfFile: $0) }
            }.accessibilityHidden(true)
    }
}
