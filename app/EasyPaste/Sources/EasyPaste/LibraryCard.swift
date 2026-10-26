import AppKit
import SwiftUI

struct LibraryClipCard: View {
    @ThemePalette private var palette
    @ObservedObject var history: History
    let clip: Clip
    var list = false
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast
    private var selected: Bool { history.selected == clip.id || history.selectedIDs.contains(clip.id) }
    var body: some View {
        Group {
            if list { listContent }
            else { gridContent }
        }
        .padding(12).background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? palette.accent : (contrast == .increased ? Theme.ink.opacity(0.5) : palette.accent.opacity(hovered ? 0.32 : 0.10)), lineWidth: selected ? 2 : (contrast == .increased ? 1.5 : 0.75)))
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
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                sourceIcon
                Text(clip.source).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if history.showPasteCounts { PasteCountBadge(count: history.pasteUsage.count(for: clip.id)) }
                more
                if selected { Image(systemName: "checkmark.square.fill").font(.system(size: 18)).foregroundStyle(palette.accent).accessibilityLabel("Sélectionné") }
            }.frame(height: 23)
            preview.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            if (clip.kind == .image || clip.kind == .video), let title = clip.cardTitle {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1).help(title)
            }
            ClipCardFooter(history: history, clip: clip)
        }.frame(height: 198)
    }
    private var listContent: some View {
        HStack(spacing: 14) {
            Group {
                if clip.kind == .image || clip.kind == .video { preview }
                else {
                    Image(systemName: clip.kind.symbol).font(.system(size: 25, weight: .light)).foregroundStyle(clip.kind.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(clip.kind.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                }
            }.frame(width: 105, height: 67).clipped()
            VStack(alignment: .leading, spacing: 7) {
                Text(clip.cardTitle ?? (clip.text.isEmpty ? clip.title : String(clip.text.prefix(160)))).font(.system(size: 14, weight: .medium)).lineLimit(2)
                if let metadata = clip.imageMetadata { Text("\(metadata.dimensions) · \(metadata.fileSize)").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                HStack(spacing: 8) {
                    sourceIcon; Text(clip.source); Text("·"); Text(clip.kind.label)
                    if history.showPasteCounts { PasteCountBadge(count: history.pasteUsage.count(for: clip.id)) }
                }.font(.system(size: 11)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(ClipDate.label(clip.date)).font(.system(size: 11)).foregroundStyle(Theme.muted)
            ClipCardFooter(history: history, clip: clip).frame(width: 118); more
            if selected { Image(systemName: "checkmark.square.fill").foregroundStyle(palette.accent) }
        }
    }
    private var sourceIcon: some View {
        SourceApplicationIcon(clip: clip, size: 23)
    }
    private var more: some View {
        Menu { ClipActions(history: history, clip: clip) } label: { Image(systemName: "ellipsis").frame(width: 27, height: 24).contentShape(Rectangle()) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Actions de l’élément").accessibilityLabel("Actions de l’élément")
    }
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(clip.kind.accent.opacity(clip.kind == .text ? 0.12 : 0.05))
            ClipContent(clip: clip, compact: list, showsImageMetadata: !list).padding(clip.kind == .image || clip.kind == .video ? 0 : 13)
            if clip.kind == .video {
                Button { history.openPreview(clip) } label: { Image(systemName: "play.fill").font(.system(size: 22)).foregroundStyle(.white).frame(width: 49, height: 49).background(.black.opacity(0.65), in: Circle()) }
                    .buttonStyle(FullAreaButtonStyle()).help("Lire la vidéo").accessibilityLabel("Lire la vidéo")
                VStack { Spacer(); HStack { Spacer(); Text(clip.durationLabel).foregroundStyle(.white).font(.system(size: 11, weight: .medium, design: .monospaced)).padding(5).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 5)) } }.padding(7).allowsHitTesting(false)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
