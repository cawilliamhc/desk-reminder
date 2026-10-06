import DeskCore
import Foundation

/// Appends to serial.log, off the main thread and without growing forever.
///
/// Opened lazily and kept open: the read loop can hand over a line every
/// couple of hundred milliseconds while the desk is moving, and reopening a
/// file that often is work nobody needs.
final class SerialLogFile: @unchecked Sendable {
    static let url = Paths.support.appending(path: "serial.log")

    private let queue = DispatchQueue(label: "desk.serial.log")
    private var handle: FileHandle?
    private var written = 0

    func append(_ text: String) {
        queue.async { [weak self] in self?.write(text) }
    }

    /// A line that says the app did something, rather than the box.
    func note(_ text: String, at date: Date = Date()) {
        append(SerialLog.event(text, at: date))
    }

    func bytes(_ bytes: [UInt8], at date: Date) {
        append(SerialLog.received(bytes, at: date))
    }

    private func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if handle == nil { open() }
        guard let handle else { return }
        try? handle.write(contentsOf: data)
        written += data.count
        // Checked now and then rather than on every line: trimming means
        // reading the whole file back.
        if written > 64 * 1024 {
            written = 0
            trim()
        }
    }

    private func open() {
        let manager = FileManager.default
        try? manager.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: Self.url.path) {
            manager.createFile(atPath: Self.url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: Self.url)
        _ = try? handle?.seekToEnd()
    }

    private func trim() {
        guard let contents = try? Data(contentsOf: Self.url), contents.count > SerialLog.maxBytes
        else { return }
        try? handle?.close()
        handle = nil
        try? SerialLog.trimmed(contents).write(to: Self.url, options: .atomic)
        open()
    }

    func close() {
        queue.async { [weak self] in
            try? self?.handle?.close()
            self?.handle = nil
        }
    }
}
