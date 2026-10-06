import Foundation

/// A record of what actually came down the wire, for working out what wakes
/// the handset.
///
/// The app reports heights and throws the rest away, so nobody has ever seen
/// what else the box says - and "the handset clicks and lights up by itself"
/// is a claim about exactly that. If the box sends something of its own
/// accord, it's in here with a time against it. If the line is silent at the
/// moment of a click, the wake came from somewhere else entirely, and this
/// says that too.
public enum SerialLog {
    /// Beyond this the file is trimmed back to half, oldest first. A day of
    /// a desk moving is a few kilobytes; a fault that chatters could be
    /// anything.
    public static let maxBytes = 2 * 1024 * 1024

    public static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return String(
            format: "%02d:%02d:%02d.%03d",
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
            (parts.nanosecond ?? 0) / 1_000_000
        )
    }

    /// "14:32:07.145  rx  9 bytes  F2 F2 01 03 01 B8 07 C4 7E"
    public static func received(_ bytes: [UInt8], at date: Date, calendar: Calendar = .current) -> String {
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "\(timestamp(date, calendar: calendar))  rx  \(bytes.count) "
            + "\(bytes.count == 1 ? "byte" : "bytes")  \(hex)\n"
    }

    /// "14:32:07.145  --  port opened (cu.usbserial-BH01097T)"
    public static func event(_ text: String, at date: Date, calendar: Calendar = .current) -> String {
        "\(timestamp(date, calendar: calendar))  --  \(text)\n"
    }

    /// Keeps the tail. A log that grows without limit is one that fills a
    /// disk at three in the morning.
    public static func trimmed(_ contents: Data, max: Int = maxBytes) -> Data {
        guard contents.count > max else { return contents }
        let keep = contents.suffix(max / 2)
        guard let newline = keep.firstIndex(of: 0x0A) else { return Data(keep) }
        return Data(keep[keep.index(after: newline)...])
    }
}
