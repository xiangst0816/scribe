import CoreAudio
import Foundation

/// Persistent identifier for a CoreAudio input device. `kAudioDevicePropertyDeviceUID`
/// is stable across reboots and across the device being unplugged + replugged,
/// so it's the right thing to pin in UserDefaults.
typealias AudioDeviceUID = String

struct AudioInputDevice: Equatable {
    let id: AudioDeviceID
    let uid: AudioDeviceUID
    let name: String
}

/// User's microphone preference.
///
/// `.auto` is the default — if the current default *output* device also has
/// an input stream (Bluetooth headsets, USB headphones with built-in mics),
/// route input there. Otherwise fall through to `.systemDefault`. This keeps
/// the right-thing happening when the user wears AirPods, while still letting
/// users with a fancy USB mic pin to it explicitly.
enum MicrophonePreference: Equatable {
    case auto
    case systemDefault
    case specific(uid: AudioDeviceUID)
}

/// Resolves the user's `MicrophonePreference` to a concrete `AudioDeviceID`,
/// enumerates input-capable devices, and notifies on hardware changes.
///
/// Stateless aside from a single CoreAudio listener registration; safe to call
/// any of the static query methods from any thread.
final class MicrophoneRouter {
    static let shared = MicrophoneRouter()

    /// Posted on the main queue when the input device list changes.
    static let devicesChanged = Notification.Name("scribe.mic.devicesChanged")

    private static let prefKey = "mic.preference"
    private static let uidKey = "mic.specificUID"

    private let listenerLock = NSLock()
    private var listenerInstalled = false

    private init() {}

    // MARK: - Preference (UserDefaults)

    var preference: MicrophonePreference {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.prefKey) ?? "auto"
            switch raw {
            case "systemDefault":
                return .systemDefault
            case "specific":
                guard let uid = UserDefaults.standard.string(forKey: Self.uidKey),
                      !uid.isEmpty else { return .auto }
                return .specific(uid: uid)
            default:
                return .auto
            }
        }
        set {
            switch newValue {
            case .auto:
                UserDefaults.standard.set("auto", forKey: Self.prefKey)
                UserDefaults.standard.removeObject(forKey: Self.uidKey)
            case .systemDefault:
                UserDefaults.standard.set("systemDefault", forKey: Self.prefKey)
                UserDefaults.standard.removeObject(forKey: Self.uidKey)
            case .specific(let uid):
                UserDefaults.standard.set("specific", forKey: Self.prefKey)
                UserDefaults.standard.set(uid, forKey: Self.uidKey)
            }
        }
    }

    // MARK: - Resolution

    /// Returns the device the recording session should use, or `nil` to mean
    /// "let `AVAudioEngine.inputNode` use its built-in system-default routing".
    ///
    /// Resolution rules:
    /// - `.systemDefault` → `nil` (no override)
    /// - `.specific(uid)` → that device if still present; otherwise fall through
    ///   to the auto rules so a yanked USB mic doesn't strand the user.
    /// - `.auto` → if the default output device also exposes an input stream
    ///   (AirPods, headset mics), use it; otherwise return `nil`.
    func resolvedDeviceID() -> AudioDeviceID? {
        switch preference {
        case .systemDefault:
            return nil
        case .specific(let uid):
            if let device = Self.inputDevices().first(where: { $0.uid == uid }) {
                return device.id
            }
            return Self.outputBoundInputDeviceID()
        case .auto:
            return Self.outputBoundInputDeviceID()
        }
    }

    // MARK: - Enumeration

    /// All currently-attached audio devices that have at least one input channel.
    static func inputDevices() -> [AudioInputDevice] {
        let ids = allDeviceIDs()
        return ids.compactMap { id -> AudioInputDevice? in
            guard deviceHasInput(id) else { return nil }
            guard let uid = deviceUID(id), let name = deviceName(id) else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    // MARK: - Device-change notifications

    /// Subscribe to `kAudioHardwarePropertyDevices`. Idempotent — calling
    /// twice is a no-op. Posts `devicesChanged` on the main queue.
    func startObservingDeviceChanges() {
        listenerLock.lock()
        defer { listenerLock.unlock() }
        guard !listenerInstalled else { return }

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            // Already on main since we hand the listener .main as its queue.
            NotificationCenter.default.post(name: MicrophoneRouter.devicesChanged, object: nil)
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main,
            block
        )
        if status == noErr {
            listenerInstalled = true
        }
    }

    // MARK: - CoreAudio helpers (private)

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size
        )
        guard status == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &ids
        )
        guard status == noErr else { return [] }
        return ids
    }

    /// `kAudioDevicePropertyStreamConfiguration` returns an `AudioBufferList`
    /// whose total size we don't know ahead of time, so we ask for the size
    /// first, allocate, then query.
    private static func deviceHasInput(_ id: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr,
              size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let listPtr = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, listPtr) == noErr else {
            return false
        }
        let buffers = UnsafeMutableAudioBufferListPointer(listPtr)
        for b in buffers where b.mNumberChannels > 0 {
            return true
        }
        return false
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func deviceUID(_ id: AudioDeviceID) -> AudioDeviceUID? {
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &uid)
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &size,
            &id
        ) == noErr else { return nil }
        return id == 0 ? nil : id
    }

    /// Returns the current default output device's `AudioDeviceID` if that
    /// device also exposes an input stream — i.e. an output+input combo like
    /// AirPods, a USB headset, or a webcam with a built-in mic. Otherwise nil.
    private static func outputBoundInputDeviceID() -> AudioDeviceID? {
        guard let outID = defaultOutputDeviceID(), deviceHasInput(outID) else {
            return nil
        }
        return outID
    }
}
