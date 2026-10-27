import SwiftUI

/// Apple Pencil Pro double tap and squeeze follow the choice in Settings › Apple Pencil. Off turns
/// them off in the app too; with any other choice they keep their meaning in the calculator and
/// the definition editors (double tap deletes, squeeze toggles the symbol palette).
enum PencilGestures {
    /// Double tap deletes the character before the caret unless it is set to Off.
    static func doubleTapDeletes(preferredAction: PencilPreferredAction) -> Bool {
        preferredAction != .ignore
    }

    /// Squeeze toggles the symbol palette unless it is set to Off or runs a shortcut (the system
    /// runs the shortcut then).
    static func squeezeTogglesPalette(preferredAction: PencilPreferredAction) -> Bool {
        preferredAction != .ignore && preferredAction != .runSystemShortcut
    }
}
