import AppKit
import SwiftUI

/// Select immediately; recognise double-click independently, without holding the
/// first click for the system's double-click interval. Buttons keep their actions.
struct CardInteraction: ViewModifier {
    let history: History
    let clip: Clip

    func body(content: Content) -> some View {
        content.gesture(singleClick.simultaneously(with: TapGesture(count: 2).onEnded {
            activate(modifiers: NSApp?.currentEvent?.modifierFlags ?? NSEvent.modifierFlags)
        }))
    }

    private var singleClick: some Gesture {
        TapGesture(count: 1).onEnded {
            let event = NSApp?.currentEvent
            select(clickCount: event?.clickCount ?? 1,
                   modifiers: event?.modifierFlags ?? NSEvent.modifierFlags)
        }
    }

    @MainActor func select(clickCount: Int, modifiers: NSEvent.ModifierFlags) {
        guard clickCount == 1 else { return }
        history.select(clip, modifiers: modifiers)
        NSApp?.keyWindow?.makeFirstResponder(nil)
    }

    @MainActor func activate(modifiers: NSEvent.ModifierFlags) {
        guard modifiers.intersection([.command, .shift, .control, .option]).isEmpty,
              let current = history.clips.first(where: { $0.id == clip.id }) else { return }
        if current.trashedAt != nil { history.restore(current) }
        else { history.paste?([current], false) }
    }
}
