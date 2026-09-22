import Darwin
import Foundation

/// Reads height reports from the FTDI adapter. Receive-only by construction:
/// nothing here ever writes to the port.
///
/// The port is opened non-blocking, then has the blocking flag cleared, which
/// is the usual dance for a /dev/cu.* device. A dropped adapter surfaces as a
/// read error, and the monitor waits and looks for the port again.
public final class SerialMonitor: @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case connected(String)
        case adapterNotFound
        case disconnected

        public var label: String {
            switch self {
            case .connected(let port): "connected (\(port))"
            case .adapterNotFound: "adapter not found"
            case .disconnected: "adapter disconnected"
            }
        }
    }

    public static let portGlob = "/dev/cu.usbserial"
    private let baud: speed_t = 9600
    private let onHeight: @Sendable (Double, Date) -> Void
    private let onStatus: @Sendable (Status) -> Void
    private let queue = DispatchQueue(label: "desk.serial")
    private var stopped = false

    public init(
        onHeight: @escaping @Sendable (Double, Date) -> Void,
        onStatus: @escaping @Sendable (Status) -> Void
    ) {
        self.onHeight = onHeight
        self.onStatus = onStatus
    }

    /// First /dev/cu.usbserial* device, if the adapter is plugged in.
    public static func findPort() -> String? {
        let dev = "/dev/"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dev)) ?? []
        return names
            .filter { $0.hasPrefix("cu.usbserial") }
            .sorted()
            .first
            .map { dev + $0 }
    }

    public func start() {
        queue.async { [weak self] in self?.loop() }
    }

    public func stop() {
        queue.sync { stopped = true }
    }

    private func loop() {
        while !stopped {
            guard let port = Self.findPort() else {
                onStatus(.adapterNotFound)
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            guard let fd = open(port: port) else {
                onStatus(.disconnected)
                Thread.sleep(forTimeInterval: 5)
                continue
            }
            onStatus(.connected((port as NSString).lastPathComponent))
            read(fd: fd)
            close(fd)
            onStatus(.disconnected)
            Thread.sleep(forTimeInterval: 5)
        }
    }

    private func open(port: String) -> Int32? {
        let fd = Darwin.open(port, O_RDONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        guard fcntl(fd, F_SETFL, 0) >= 0 else { close(fd); return nil }

        var options = termios()
        guard tcgetattr(fd, &options) == 0 else { close(fd); return nil }
        cfmakeraw(&options)
        cfsetispeed(&options, baud)
        cfsetospeed(&options, baud)
        options.c_cflag |= tcflag_t(CREAD | CLOCAL)      // read, ignore modem lines
        options.c_cflag &= ~tcflag_t(CSTOPB | PARENB)    // 8N1
        withUnsafeMutableBytes(of: &options.c_cc) { cc in
            cc[Int(VMIN)] = 0
            cc[Int(VTIME)] = 2                           // 0.2 s read timeout
        }
        guard tcsetattr(fd, TCSANOW, &options) == 0 else { close(fd); return nil }
        tcflush(fd, TCIFLUSH)
        return fd
    }

    private func read(fd: Int32) {
        var parser = FrameParser()
        var buffer = [UInt8](repeating: 0, count: 256)
        while !stopped {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, 256) }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return      // adapter unplugged, or the port went away
            }
            guard n > 0 else { continue }
            let now = Date()
            for frame in parser.feed(Array(buffer[0..<n])) {
                if let height = frame.height { onHeight(height, now) }
            }
        }
    }
}
