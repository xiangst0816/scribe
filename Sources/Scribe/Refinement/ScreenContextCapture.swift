import Foundation

/// Public entry-point for the screen-context feature. Captures the focused
/// window's contents at the moment the user pressed Fn and returns it as
/// a single string the polish prompt can fold in as a "what the user is
/// looking at" reference.
///
/// Implementation: `OCRContextSource` — captures the focused window via
/// ScreenCaptureKit and runs `VNRecognizeTextRequest`. Catches everything
/// visually rendered, including canvas surfaces (VS Code editor, Figma,
/// game UIs) that AX-tree traversal can't see. Costs a Screen Recording
/// permission.
///
/// We previously prototyped an AX-tree source. It worked for native
/// AppKit apps but on macOS 26 + VS Code returned only window chrome
/// even with the documented `AXEnhancedUserInterface` /
/// `AXManualAccessibility` flags set; the AXObserver-presence trick that
/// would have unlocked Chromium's full a11y tree was viable but added
/// runtime complexity for a strategy still blind to non-DOM canvases.
/// Net assessment: OCR is the simpler and more reliably general path.
enum ScreenContextCapture {
    static func capture() async -> String? {
        await OCRContextSource.capture()
    }

    /// Append one line to ~/Library/Logs/Scribe.log under the
    /// `screen-context:` tag. Sources call this for every lifecycle event
    /// — started / captured / cancelled / empty / collected / error —
    /// so the log file is the single place to look for "what did Scribe
    /// see, and how long did it take" answers. NSLog gets redacted as
    /// `<private>` for ad-hoc-signed apps on macOS 26; file IO sidesteps
    /// the privacy filter so we can actually debug.
    static func log(_ message: String) {
        appendToLog("\(ISO8601DateFormatter().string(from: Date())) screen-context: \(message)\n")
    }

    /// Dump the full OCR-recognized text into the log between `begin` /
    /// `end` markers so a `tail -f` reader sees exactly what the model
    /// will receive as `screenContext`. Used when the user wants to
    /// verify "did OCR really pick up that file name?" — `head=...` in
    /// the summary line is just the first 200 chars.
    static func logFullText(_ body: String, source: String, bundleID: String) {
        let begin = "\(ISO8601DateFormatter().string(from: Date())) screen-context: [\(source)] full-text begin bundle=\(bundleID) chars=\(body.count) ─────────\n"
        let bodyBlock = body.hasSuffix("\n") ? body : body + "\n"
        let end = "\(ISO8601DateFormatter().string(from: Date())) screen-context: [\(source)] full-text end ─────────\n"
        appendToLog(begin + bodyBlock + end)
    }

    private static func appendToLog(_ text: String) {
        let url = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Scribe.log")
        guard let data = text.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url)
            return
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}

/// One screen-context strategy. Implementations are stateless namespaces
/// (enums) — any per-source caching belongs in a separate type so the
/// strategies stay pure functions of "current frontmost window state".
protocol ScreenContextSource {
    /// Stable identifier used in logs. e.g. "ocr".
    static var identifier: String { get }

    /// One-shot capture. Returns nil on any failure or empty result.
    /// Implementations are responsible for their own logging via
    /// `ScreenContextCapture.log(_:)`.
    static func capture() async -> String?
}
