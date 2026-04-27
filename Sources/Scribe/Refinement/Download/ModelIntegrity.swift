import Foundation
import CryptoKit

/// Streaming SHA-256 verification. `loadFile` keeps memory bounded — we read
/// 1 MiB chunks rather than holding 1 GB in RAM.
///
/// Per design doc §4.6, integrity is **not** best-effort: if the descriptor
/// is pinned (non-empty hash) and the bytes don't match, the file is rejected.
/// On a non-pinned descriptor (developer-build placeholder), we surface that
/// fact so callers can refuse to mark the file ready.
enum ModelIntegrity {
    enum Result: Equatable {
        case match
        case mismatch(actual: String, expected: String)
        case notPinned             // descriptor has no hash yet
        case ioError(String)

        var isAcceptable: Bool {
            switch self {
            case .match: return true
            default:     return false
            }
        }
    }

    static func verify(fileURL: URL, against descriptor: ModelDescriptor) -> Result {
        guard descriptor.isPinned else { return .notPinned }
        do {
            let actual = try sha256Hex(of: fileURL)
            if actual.lowercased() == descriptor.expectedSHA256.lowercased() {
                return .match
            }
            return .mismatch(actual: actual, expected: descriptor.expectedSHA256)
        } catch {
            return .ioError(error.localizedDescription)
        }
    }

    /// Streaming SHA-256 — reads the file 1 MiB at a time so verification of
    /// a 1 GB model never holds more than ~1 MiB in memory.
    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 1 << 20  // 1 MiB
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) { /* loop body lives in the autoreleasepool to bound memory */ }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
