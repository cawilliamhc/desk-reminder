import Foundation

/// Height reports a Jiecang JCB35NH4A sends on its F port (pin 4), 9600 8N1:
///
///     F2 F2 | cmd | len | data[len] | checksum | 7E
///     checksum = (cmd + len + sum(data)) & 0xFF
///
/// Command 0x01 is a height report: two big-endian bytes, tenths of an inch.
/// The box is silent unless the desk is moving (plus ~1-2 s after it stops).
public struct DeskFrame: Equatable, Sendable {
    public let command: UInt8
    public let data: [UInt8]

    /// Height in inches for a height report, otherwise nil.
    public var height: Double? {
        guard command == 0x01, data.count >= 2 else { return nil }
        return Double(Int(data[0]) << 8 | Int(data[1])) / 10
    }
}

/// Feed bytes in as they arrive; get complete, checksum-valid frames out.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ chunk: [UInt8]) -> [DeskFrame] {
        buffer += chunk
        var frames: [DeskFrame] = []
        while true {
            guard let start = headerIndex() else {
                // Keep a trailing F2: it may be the first half of a header.
                buffer = buffer.suffix(1)
                return frames
            }
            buffer.removeFirst(start)
            guard buffer.count >= 4 else { return frames }
            let command = buffer[2]
            let length = Int(buffer[3])
            let end = 4 + length + 2
            guard buffer.count >= end else { return frames }

            let data = Array(buffer[4..<(4 + length)])
            let sum = UInt8((Int(command) + length + data.reduce(0) { $0 + Int($1) }) & 0xFF)
            if buffer[end - 1] == 0x7E, buffer[end - 2] == sum {
                frames.append(DeskFrame(command: command, data: data))
                buffer.removeFirst(end)
            } else {
                // Not a real frame. Drop one byte only: in "F2 F2 F2 ..." the
                // real header may start at the second F2.
                buffer.removeFirst(1)
            }
        }
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for i in 0...(buffer.count - 2) where buffer[i] == 0xF2 && buffer[i + 1] == 0xF2 {
            return i
        }
        return nil
    }
}
