import CoreAudio
import Foundation

public struct AudioProcessInfo {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String
}

public enum CA {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type = T.self) -> T? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, raw) == noErr else { return nil }
        return raw.load(as: T.self)
    }

    static func getString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        guard let ref: Unmanaged<CFString> = get(object, selector) else { return nil }
        return ref.takeRetainedValue() as String
    }

    public static func processes() -> [AudioProcessInfo] {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let pid: pid_t = get(id, kAudioProcessPropertyPID),
                  let bundle = getString(id, kAudioProcessPropertyBundleID) else { return nil }
            return AudioProcessInfo(objectID: id, pid: pid, bundleID: bundle)
        }
    }

    public static func defaultOutputDeviceUID() -> String? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let device: AudioObjectID = get(system, kAudioHardwarePropertyDefaultSystemOutputDevice),
              device != kAudioObjectUnknown else { return nil }
        return getString(device, kAudioDevicePropertyDeviceUID)
    }
}
