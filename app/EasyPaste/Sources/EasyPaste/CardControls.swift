import AppKit
import SwiftUI

struct ClipCardFooter: View {
    @ObservedObject var history: History
    let clip: Clip
    var quickIndex: Int? = nil

    var body: some View {
        HStack(spacing: 6) {
            if clip.hasPreview {
                action("Aperçu", symbol: "eye", help: "Aperçu · Espace") { history.openPreview(clip) }
            }
            if let url = clip.originURL {
                action("Ouvrir la page d’origine", symbol: "globe", help: "Page d’origine · \(url.host ?? url.absoluteString)") { NSWorkspace.shared.open(url) }
            }
            Spacer(minLength: 4)
            if let index = quickIndex, index < 9 {
                Text("⌘\(index + 1)").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.muted).padding(.trailing, 3).accessibilityHidden(true)
            }
            action(clip.pinned ? "Retirer des favoris" : "Ajouter aux favoris",
                   symbol: clip.pinned ? "star.fill" : "star", tint: clip.pinned ? Theme.colors[2] : Theme.muted) {
                history.togglePin(clip)
            }.disabled(clip.trashedAt != nil)
            action(clip.trashedAt == nil ? "Mettre à la corbeille" : "Supprimer définitivement", symbol: "trash", tint: Theme.danger) {
                if clip.trashedAt == nil { history.requestTrash([clip]) }
                else { confirmPermanentDeletion(history, items: [clip]) }
            }
        }.frame(height: 30)
    }

    private func action(_ title: String, symbol: String, tint: Color = Theme.muted,
                        help: String? = nil, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint).frame(width: 30, height: 30)
        }.buttonStyle(FullAreaButtonStyle()).help(help ?? title).accessibilityLabel(title)
    }
}

struct TrashDecision {
    var approved: Bool
    var skipFuture = false
}

@MainActor enum TrashConfirmation {
    static func ask(count: Int) -> TrashDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count == 1 ? "Mettre cet élément à la corbeille ?" : "Mettre ces \(count) éléments à la corbeille ?"
        alert.informativeText = "Tu pourras les restaurer depuis la corbeille. Les fichiers d’origine sont conservés."
        alert.addButton(withTitle: "Mettre à la corbeille")
        alert.addButton(withTitle: "Annuler").keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Ne plus demander"
        let approved = alert.runModal() == .alertFirstButtonReturn
        return TrashDecision(approved: approved, skipFuture: alert.suppressionButton?.state == .on)
    }
}

extension History {
    /// Shared by card controls, menus, selection toolbar and the Delete key.
    /// Suppression applies to recoverable trash only, never permanent deletion.
    func requestTrash(_ items: [Clip], confirm: @MainActor (Int) -> TrashDecision = TrashConfirmation.ask) {
        guard !fault else { return }
        let ids = Set(items.map(\.id))
        let current = clips.filter { ids.contains($0.id) && $0.trashedAt == nil }
        guard !current.isEmpty else { return }
        if confirmTrash {
            let decision = confirm(current.count)
            guard decision.approved else { return }
            if decision.skipFuture { confirmTrash = false }
        }
        trashItems(current)
    }
}
