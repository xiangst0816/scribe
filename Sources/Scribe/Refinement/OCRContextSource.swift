import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

/// Captures the focused window's pixels and runs `VNRecognizeTextRequest`
/// on them. Catches the surfaces AX can't see — VS Code's editor canvas,
/// Chrome web pages without ARIA, anything rendered to a custom layer.
///
/// Costs:
/// - **Screen Recording permission** (TCC). Scribe needs to be approved in
///   System Settings → Privacy & Security → Screen & System Audio Recording.
///   First call prompts the user; without permission, every call is a
///   logged no-op and polish runs without context.
/// - Per-call latency: ~200–800 ms on Apple Silicon for a typical 13" or
///   16" laptop screen at retina resolution. Way longer than AX, but the
///   capture starts at Fn-down so it has the entire recording duration to
///   complete; the 200 ms `awaitScreenContext` deadline only kicks in if
///   OCR somehow stalls beyond what the user spoke.
///
/// Recognition language list is hard-coded to `["zh-Hans", "en-US"]` for
/// now — both are read out by Vision's accurate path on macOS 14+. We can
/// route from the user's selected dictation locale later if needed.
enum OCRContextSource: ScreenContextSource {
    static let identifier = "ocr"

    /// Hard cap on returned characters. Sized against Gemma 4 E2B's 4 K-
    /// token context window minus the rest of the polish prompt (system
    /// prompt ~800 tokens, user transcript ~200-500, generated output
    /// ~300). 2500 chars ≈ 2500 tokens of CJK leaves comfortable margin
    /// after the noise filter strips icons / chevrons / garbage symbols
    /// from the raw Vision output. A previous 3000-char cap with no
    /// filter and a too-small `n_batch=2048` crashed `llama_decode`.
    static let maxChars = 2500

    static func capture() async -> String? {
        let started = Date()

        // Permission gate. CGPreflight does NOT prompt; only CGRequest does.
        // We intentionally call Request on a denied call so the user's next
        // attempt has a chance to succeed — the system prompt only appears
        // once per app lifetime, so an early "permission flap" call here is
        // the cheapest way to surface the dialog.
        guard CGPreflightScreenCaptureAccess() else {
            ScreenContextCapture.log("[ocr] denied — Screen Recording permission missing; triggering system prompt")
            _ = CGRequestScreenCaptureAccess()
            return nil
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            ScreenContextCapture.log("[ocr] skipped — no frontmost app")
            return nil
        }
        let bundleID = app.bundleIdentifier ?? "?"
        let pid = app.processIdentifier
        ScreenContextCapture.log("[ocr] started bundle=\(bundleID) pid=\(pid)")

        // Find the frontmost regular window owned by the focused app.
        let scWindow: SCWindow
        do {
            let content = try await SCShareableContent.current
            let candidates = content.windows.filter { w in
                w.owningApplication?.processID == pid
                    && w.windowLayer == 0  // 0 = regular app window (filters menu-bar/HUDs)
                    && w.isOnScreen
            }
            guard let first = candidates.first else {
                ScreenContextCapture.log("[ocr] no-window bundle=\(bundleID) candidates=0 windows=\(content.windows.count)")
                return nil
            }
            scWindow = first
        } catch {
            ScreenContextCapture.log("[ocr] shareable-content-error bundle=\(bundleID) error=\(error.localizedDescription)")
            return nil
        }

        if Task.isCancelled {
            ScreenContextCapture.log("[ocr] cancelled bundle=\(bundleID) stage=pre-capture duration=\(durationMs(since: started))ms")
            return nil
        }

        // Capture pixels.
        //
        // SCWindow.frame is in **points**, but SCStreamConfiguration.width/
        // height are in **pixels**. On Retina screens that's a 2× under-
        // sample — Vision then receives a ~709×437 thumbnail of a Notes
        // window that should have been 1418×874, and OCR fails to read
        // smaller body text. Multiply by the backing scale factor of the
        // screen the window is actually on (fall back to main, then 2×).
        let scale = scaleFactor(for: scWindow.frame)
        let pixelWidth = Int(scWindow.frame.width * scale)
        let pixelHeight = Int(scWindow.frame.height * scale)
        let cgImage: CGImage
        do {
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = pixelWidth
            config.height = pixelHeight
            config.showsCursor = false
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            ScreenContextCapture.log("[ocr] capture-error bundle=\(bundleID) error=\(error.localizedDescription) scale=\(scale)")
            return nil
        }

        if Task.isCancelled {
            ScreenContextCapture.log("[ocr] cancelled bundle=\(bundleID) stage=post-capture duration=\(durationMs(since: started))ms")
            return nil
        }

        let captureMs = durationMs(since: started)
        ScreenContextCapture.log("[ocr] captured bundle=\(bundleID) size=\(cgImage.width)x\(cgImage.height) frame=\(Int(scWindow.frame.width))x\(Int(scWindow.frame.height))pt scale=\(scale)x duration=\(captureMs)ms")

        // Run Vision OCR on a background queue.
        let ocrStart = Date()
        let recognized = await runOCR(on: cgImage)
        let ocrMs = durationMs(since: ocrStart)

        if Task.isCancelled {
            ScreenContextCapture.log("[ocr] cancelled bundle=\(bundleID) stage=post-ocr ocrDuration=\(ocrMs)ms")
            return nil
        }

        guard let text = recognized, !text.isEmpty else {
            ScreenContextCapture.log("[ocr] empty bundle=\(bundleID) ocrDuration=\(ocrMs)ms")
            return nil
        }

        let trimmed = text.count > Self.maxChars
            ? String(text.prefix(Self.maxChars))
            : text
        let truncated = text.count > Self.maxChars
        let preview = String(trimmed.prefix(200))
            .replacingOccurrences(of: "\n", with: "⏎")
        ScreenContextCapture.log("[ocr] collected bundle=\(bundleID) chars=\(trimmed.count) truncated=\(truncated) captureMs=\(captureMs) ocrMs=\(ocrMs) totalMs=\(durationMs(since: started)) head=\"\(preview)\"")
        // Dump the exact text the polish prompt is about to consume so the
        // user can grep / scroll through what OCR actually picked up.
        // Spans multiple lines — wrapped in begin/end markers so it stays
        // greppable in `tail -f`.
        ScreenContextCapture.logFullText(trimmed, source: "ocr", bundleID: bundleID)
        return trimmed
    }

    // MARK: - Private

    private static func runOCR(on image: CGImage) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    ScreenContextCapture.log("[ocr] vision-error \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                // Top candidate per observation, joined by newline so visual
                // rows stay separate. Vision orders observations roughly
                // top-to-bottom which preserves reading order.
                //
                // Filter noise: VS Code / Chrome sidebars are full of SF
                // Symbol icons (chevrons, badges, file-type glyphs) that
                // Vision tries to OCR as `©Q`, `V`, `>`, `〉`, `弱£的°` etc.
                // These add nothing useful for term disambiguation and
                // gobble the char budget that should go to actual editor /
                // tab / file-name content. Heuristic: drop observations
                // whose recognized text is < 2 chars after trimming, OR
                // contains zero letter/digit characters (pure symbol
                // garbage). Chinese / Japanese / Korean characters all
                // count as letters so CJK-only labels survive.
                let rawLines = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                let filteredLines = rawLines.filter { line in
                    line.count >= 2 && line.unicodeScalars.contains(where: {
                        CharacterSet.letters.contains($0)
                            || CharacterSet.decimalDigits.contains($0)
                    })
                }
                ScreenContextCapture.log("[ocr] vision-output observations=\(observations.count) raw-lines=\(rawLines.count) filtered-lines=\(filteredLines.count)")
                continuation.resume(returning: filteredLines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                ScreenContextCapture.log("[ocr] vision-perform-error \(error.localizedDescription)")
                continuation.resume(returning: nil)
            }
        }
    }

    private static func durationMs(since started: Date) -> Int {
        Int(Date().timeIntervalSince(started) * 1000)
    }

    /// Backing scale factor of the screen containing the window's center.
    /// `NSScreen.frame` is in Cocoa coordinates (bottom-left origin) while
    /// `SCWindow.frame` is in CG coordinates (top-left origin), so we flip
    /// the y axis before doing a contains-check. Falls back to main
    /// screen, then 2× — most current Macs are Retina.
    private static func scaleFactor(for windowFrame: CGRect) -> CGFloat {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaY = primaryHeight - windowFrame.midY
        let center = CGPoint(x: windowFrame.midX, y: cocoaY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }
}
