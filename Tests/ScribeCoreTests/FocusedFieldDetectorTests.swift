import Testing
@testable import ScribeCore

/// Covers `FocusedFieldDetector.classify` — the pure mapping from
/// (role, subrole, settable) to "is this a text-editable AX element."
/// The live `hasEditableTextFocus()` path queries the system AX server
/// and isn't unit-testable; this suite locks in the classification matrix
/// instead, which is where regressions would actually land.
@Suite struct FocusedFieldDetectorTests {

    // Native AppKit / SwiftUI text controls.
    @Test func textFieldRoleIsEditable() {
        #expect(FocusedFieldDetector.classify(role: "AXTextField", subrole: nil, valueIsSettable: false))
    }

    @Test func textAreaRoleIsEditable() {
        #expect(FocusedFieldDetector.classify(role: "AXTextArea", subrole: nil, valueIsSettable: false))
    }

    @Test func comboBoxRoleIsEditable() {
        #expect(FocusedFieldDetector.classify(role: "AXComboBox", subrole: nil, valueIsSettable: false))
    }

    // Search fields surface as role=AXTextField + subrole=AXSearchField; cover
    // the subrole branch for completeness.
    @Test func searchFieldSubroleIsEditable() {
        #expect(FocusedFieldDetector.classify(role: "AXTextField", subrole: "AXSearchField", valueIsSettable: false))
    }

    // Password fields: paste is allowed on purpose. The user pressed Fn while
    // focused on a secure field — honour their choice instead of silently
    // diverting to clipboard-only.
    @Test func secureTextFieldSubroleIsEditable() {
        #expect(FocusedFieldDetector.classify(role: "AXTextField", subrole: "AXSecureTextField", valueIsSettable: false))
    }

    // Web `<input>` / `<textarea>` in Safari/Chrome surface with one of the
    // text roles above, so they're already covered. Web `contenteditable`
    // divs and many Electron text inputs surface as AXGroup/AXWebArea but
    // expose a settable AXValue — this is the catch-all that keeps them
    // working.
    @Test func settableValueOnGenericRoleIsEditable() {
        #expect(FocusedFieldDetector.classify(role: "AXGroup", subrole: nil, valueIsSettable: true))
        #expect(FocusedFieldDetector.classify(role: "AXWebArea", subrole: nil, valueIsSettable: true))
    }

    // Non-text controls: buttons, images, static text, lists.
    @Test func nonTextRolesAreNotEditable() {
        #expect(!FocusedFieldDetector.classify(role: "AXButton", subrole: nil, valueIsSettable: false))
        #expect(!FocusedFieldDetector.classify(role: "AXImage", subrole: nil, valueIsSettable: false))
        #expect(!FocusedFieldDetector.classify(role: "AXStaticText", subrole: nil, valueIsSettable: false))
        #expect(!FocusedFieldDetector.classify(role: "AXOutline", subrole: nil, valueIsSettable: false))
    }

    // Defensive: if the focused element doesn't expose a role at all but
    // somehow does report a settable AXValue, treat that as editable.
    @Test func nilRoleWithSettableValueIsEditable() {
        #expect(FocusedFieldDetector.classify(role: nil, subrole: nil, valueIsSettable: true))
    }

    // Defensive: nothing known, nothing settable → not editable.
    @Test func nilEverythingIsNotEditable() {
        #expect(!FocusedFieldDetector.classify(role: nil, subrole: nil, valueIsSettable: false))
    }
}
