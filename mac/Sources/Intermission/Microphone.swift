import CoreAudio
import Foundation

/// Whether anything on this Mac is listening to a microphone.
///
/// The schedule knows when a session was *booked*; it doesn't know that the
/// eleven o'clock is still going at ten past twelve. A live microphone does,
/// and it covers the calls that were never in Practice Studio at all.
///
/// CoreAudio answers this without any permission of its own: it's a property
/// of the device, not of the audio. Nothing is recorded, and nothing is read
/// about what's being said.
enum Microphone {
    static var isInUse: Bool {
        inputDevices.contains { isRunning($0) }
    }

    private static func isRunning(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    /// Every device that can capture, not just the default one: Zoom is
    /// often pointed at a headset while the Mac's default is still its own
    /// microphone.
    private static var inputDevices: [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices
        ) == noErr else { return [] }

        return devices.filter { hasInput($0) }
    }

    private static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0
        else { return false }

        let buffers = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffers.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffers) == noErr
        else { return false }

        let list = UnsafeMutableAudioBufferListPointer(buffers.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }
}
