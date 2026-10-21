import AppKit
import SwiftUI

/// The shelf pastes on one click. Library cards select immediately and paste on
/// double-click. Child buttons, menus and dragging keep their own interactions.
struct CardInteraction: ViewModifier {
    let history: History
    let clip: Clip
    var pasteOnClick = false

    func body(content: Content) -> some View {
        if pasteOnClick {
            content.gesture(singleClick)
        } else {
            content.gesture(singleClick.simultaneously(with: TapGesture(count: 2).onEnded {
                if clip.trashedAt != nil { history.restore(clip) }
                else { history.paste?([clip], false) }
            }))
        }
    }

    private var singleClick: some Gesture {
        TapGesture(count: 1).onEnded {
            let event = NSApp.currentEvent
            select(clickCount: event?.clickCount ?? 1,
                   modifiers: event?.modifierFlags ?? NSEvent.modifierFlags)
        }
    }

    @MainActor func select(clickCount: Int, modifiers: NSEvent.ModifierFlags) {
        guard clickCount == 1 else { return }
        history.select(clip, modifiers: modifiers)
        NSApp.keyWindow?.makeFirstResponder(nil)
        if pasteOnClick, clip.trashedAt == nil,
           modifiers.intersection([.command, .shift, .control]).isEmpty {
            history.paste?([clip], false)
        }
    }
}
