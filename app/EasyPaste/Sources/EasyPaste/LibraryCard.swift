import AppKit
import SwiftUI

struct LibraryClipCard: View {
    @ObservedObject var history: History
    let clip: Clip
    var list = false
    @State private var hovered = false
    private var selected: Bool { history.selected == clip.id || history.selectedIDs.contains(clip.id) }
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
        .accessibilityHint("Double-clique pour coller. Espace pour l’aperçu.")
        .accessibilityAction(named: Text("Coller")) { CardInteraction(history: history, clip: clip).activate(modifiers: []) }
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
            ClipCardFooter(history: history, clip: clip)
        }.frame(height: 228)
    }
    private var listContent: some View {
        HStack(spacing: 14) {
            preview.frame(width: 105, height: 67).clipped()
            VStack(alignment: .leading, spacing: 7) {
                Text(clip.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                HStack(spacing: 8) { sourceIcon; Text(clip.source); Text("·"); Text(clip.kind.label) }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(ClipDate.label(clip.date)).font(.system(size: 11)).foregroundStyle(Theme.muted)
            ClipCardFooter(history: history, clip: clip).frame(width: 118); more
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
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(clip.kind.accent.opacity(clip.kind == .text ? 0.12 : 0.05))
            ClipContent(clip: clip, compact: list).padding(clip.kind == .image || clip.kind == .video ? 0 : 13)
            if clip.kind == .video {
                Button { history.openPreview(clip) } label: { Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white).frame(width: 49, height: 49).background(.black.opacity(0.65), in: Circle()) }
                    .buttonStyle(FullAreaButtonStyle()).help("Lire la vidéo").accessibilityLabel("Lire la vidéo")
                VStack { Spacer(); HStack { Spacer(); Text(clip.durationLabel).foregroundStyle(.white).font(.system(size: 11, weight: .medium, design: .monospaced)).padding(5).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5)) } }.padding(7).allowsHitTesting(false)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
