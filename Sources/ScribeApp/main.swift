import AppKit
import ScribeCore

// Top-level code in main.swift is non-isolated by default; AppDelegate's init
// is MainActor-isolated. NSApplication.run() is the main actor anyway, so the
// hop is purely a type-system formality.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
