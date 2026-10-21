import AppKit
import SwiftUI

/// Both recognizers run together: selecting never waits for the system's
/// double-click timeout. Child controls still take priority over the card.
struct CardInteraction: ViewModifier {
    let history: History
    let clip: Clip

    func body(content: Content) -> some View {
        content.gesture(
            TapGesture(count: 1).onEnded {
                let event = NSApp.currentEvent
                select(clickCount: event?.clickCount ?? 1,
                       modifiers: event?.modifierFlags ?? NSEvent.modifierFlags)
            }.simultaneously(with: TapGesture(count: 2).onEnded {
                if clip.trashedAt != nil { history.restore(clip) }
                else { history.paste?([clip], false) }
            })
        )
    }

    @MainActor func select(clickCount: Int, modifiers: NSEvent.ModifierFlags) {
        // The first click already selected the card. Toggling a Command-click
        // again on the second click would undo the user's multiple selection.
        guard clickCount == 1 else { return }
        history.select(clip, modifiers: modifiers)
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
