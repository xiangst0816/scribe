import AppKit
import ApplicationServices

/// Decides whether the system-wide AX focus is currently on something that
/// can accept synthesized text input.
///
/// `AppDelegate` consults this just before delivering a polished transcript
/// — when the answer is `false`, the transcript is copied to the clipboard
/// instead of being pasted, so the user can paste it manually wherever they
/// land next.
///
/// **Bias**: the function returns `true` whenever AX gives an indeterminate
/// answer (permission revoked mid-session, app doesn't implement AX, generic
/// errors). Pasting on uncertainty preserves the historical behaviour from
/// before this branch existed; falling back to "copy only" on every AX
/// hiccup would silently break the common case for users on apps with quirky
/// accessibility implementations. We only switch to copy-only when AX
/// affirmatively reports "no focused element" or "the focused element is
/// not text-editable".
enum FocusedFieldDetector {
    /// `true` if there is a focusable text input we can paste into, or if
    /// AX status is uncertain. `false` only when AX confirms the focus is
    /// not a text-editable target.
    static func hasEditableTextFocus() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        switch status {
        case .success:
            guard let focused = focusedRef,
                  CFGetTypeID(focused) == AXUIElementGetTypeID() else {
                return true
            }
            let element = focused as! AXUIElement
            return inspect(element)
        case .noValue:
            // App is frontmost but has no focused UI element (e.g. Finder
            // showing the desktop, a media player resting on its play
            // button). Nothing to paste into — fall through to copy-only.
            return false
        default:
            // permission flapped, AX disabled for this process, or the app
            // simply doesn't implement the attribute. Don't punish the user
            // for a quirky target — paste as we always have.
            return true
        }
    }

    /// Pure classifier exposed for tests. Returns `true` when the
    /// (role, subrole, settable) tuple indicates a text-editable element.
    ///
    /// Coverage:
    /// - Native AppKit/SwiftUI text fields → role match.
    /// - HTML `<input>` / `<textarea>` in Safari/Chrome → role match
    ///   (WebKit/Blink expose AXTextField / AXTextArea).
    /// - `contenteditable` divs, Electron text inputs, VS Code editor
    ///   surface → role is typically `AXGroup`/`AXWebArea` but `AXValue`
    ///   is settable, so the settable branch catches them.
    /// - Password fields surface as role=`AXTextField`, subrole=`AXSecureTextField`
    ///   — treated as text input on purpose: the user pressed Fn while
    ///   focused on a password field, so honour the paste.
    static func classify(role: String?, subrole: String?, valueIsSettable: Bool) -> Bool {
        if let role,
           role == kAXTextFieldRole as String
            || role == kAXTextAreaRole as String
            || role == kAXComboBoxRole as String {
            return true
        }
        if let subrole,
           subrole == kAXSearchFieldSubrole as String
            || subrole == "AXSecureTextField" {
            return true
        }
        return valueIsSettable
    }

    // MARK: - Private

    private static func inspect(_ element: AXUIElement) -> Bool {
        let role = copyStringAttribute(element, kAXRoleAttribute as CFString)
        let subrole = copyStringAttribute(element, kAXSubroleAttribute as CFString)
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return classify(role: role, subrole: subrole, valueIsSettable: settable.boolValue)
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &ref) == .success else {
            return nil
        }
        return ref as? String
    }
}
