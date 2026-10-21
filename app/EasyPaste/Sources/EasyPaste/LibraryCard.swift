import AppKit
import SwiftUI

struct LibraryClipCard: View {
    @ObservedObject var history: History
    let clip: Clip
    var list = false
    @State private var hovered = false
    private var selected: Bool { history.selected == clip.id || history.selectedIDs.contains(clip.id) }
    private var metadata: String {
        if clip.kind == .video { return "VIDÉO · " + clip.durationLabel }
        if clip.kind == .image { return clip.parentID != nil ? "IMAGE MODIFIÉE" : history.originalIDs.contains(clip.id) ? "IMAGE ORIGINALE" : "IMAGE" }
        if clip.kind == .text { return "TEXTE · \(clip.text.count) caractères" }
        return clip.kind == .file ? "FICHIER" : clip.kind == .color ? "COULEUR" : "LIEN"
    }
    var body: some View {
        Group {
            if list { listContent }
            else { gridContent }
        }
        .padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Theme.mint : (hovered ? Theme.hoverBorder : Theme.border), lineWidth: selected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .modifier(CardInteraction(history: history, clip: clip))
        .onHover { hovered = $0 }
        .contextMenu { ClipActions(history: history, clip: clip) }
        .onDrag { DragProvider.make(clip, history: history) }
        .accessibilityElement(children: .contain).accessibilityLabel("\(clip.title), \(clip.kind.label), \(clip.source)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction { history.select(clip) }
    }
    private var gridContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sourceIcon
                Text(clip.source).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0); more
                if selected { Image(systemName: "checkmark.square.fill").font(.system(size: 18)).foregroundStyle(Theme.mint).accessibilityLabel("Sélectionné") }
            }.frame(height: 23)
            preview.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            if clip.kind != .text && clip.kind != .color {
                Text(clip.title).font(.system(size: 13, weight: .medium)).lineLimit(1).help(clip.title)
            }
            HStack(spacing: 6) {
                Image(systemName: clip.kind.symbol).font(.system(size: 12))
                Text(metadata).font(.system(size: 9, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text(ClipDate.label(clip.date)).font(.system(size: 10)).lineLimit(1)
                favorite
            }.foregroundStyle(Theme.muted).frame(height: 22)
        }.frame(height: 228)
    }
    private var listContent: some View {
        HStack(spacing: 14) {
            preview.frame(width: 105, height: 67).clipped()
            VStack(alignment: .leading, spacing: 7) {
                Text(clip.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                HStack(spacing: 8) { sourceIcon; Text(clip.source); Text("·"); Text(metadata) }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(ClipDate.label(clip.date)).font(.system(size: 11)).foregroundStyle(Theme.muted)
            favorite; more
            if selected { Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.mint) }
        }
    }
    private var sourceIcon: some View {
        Image(systemName: clip.kind.symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(clip.kind.accent)
            .frame(width: 23, height: 23).background(clip.kind.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
    private var more: some View {
        Menu { ClipActions(history: history, clip: clip) } label: { Image(systemName: "ellipsis").frame(width: 27, height: 24).contentShape(Rectangle()) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Actions de l’élément").accessibilityLabel("Actions de l’élément")
    }
    private var favorite: some View {
        Button { history.mutate(clip.id) { $0.pinned.toggle() } } label: {
            Image(systemName: clip.pinned ? "star.fill" : "star").foregroundStyle(clip.pinned ? Theme.colors[2] : Theme.muted).frame(width: 25, height: 25)
        }.buttonStyle(FullAreaButtonStyle()).help(clip.pinned ? "Retirer des favoris" : "Ajouter aux favoris").accessibilityLabel(clip.pinned ? "Retirer des favoris" : "Ajouter aux favoris").disabled(clip.trashedAt != nil)
    }
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(clip.kind.accent.opacity(clip.kind == .text ? 0.12 : 0.05))
            ClipContent(clip: clip, compact: list).padding(clip.kind == .image || clip.kind == .video ? 0 : 13)
            if clip.kind == .video {
                Button { history.previewing = clip } label: { Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white).frame(width: 49, height: 49).background(.black.opacity(0.65), in: Circle()) }
                    .buttonStyle(FullAreaButtonStyle()).help("Lire la vidéo").accessibilityLabel("Lire la vidéo")
                VStack { Spacer(); HStack { Spacer(); Text(clip.durationLabel).foregroundStyle(.white).font(.system(size: 11, weight: .medium, design: .monospaced)).padding(5).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5)) } }.padding(7).allowsHitTesting(false)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
