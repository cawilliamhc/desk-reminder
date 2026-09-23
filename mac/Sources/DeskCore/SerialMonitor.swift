import Darwin
import Foundation

/// Reads height reports from the FTDI adapter. Receive-only by construction:
/// nothing here ever writes to the port, the port is opened read-only, and
/// DTR, RTS and break are all cleared after opening.
///
/// This matters more than it sounds. The control box reads its line going
/// low as the start of a byte, and answers with a click and a lit handset -
/// so a stray edge from opening the port is something Carl hears from across
/// the room.
///
/// The port is opened non-blocking, then has the blocking flag cleared, which
/// is the usual dance for a /dev/cu.* device. A dropped adapter surfaces as a
/// read error, and the monitor waits and looks for the port again.
public final class SerialMonitor: @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case connected(String)
        case adapterNotFound
        case disconnected

        /// For the sidebar: whether it's working, not which device it is.
        public var label: String {
            switch self {
            case .connected: "connected"
            case .adapterNotFound: "no adapter"
            case .disconnected: "adapter unplugged"
            }
        }

        /// For Settings, where the port name is the point.
        public var detail: String {
            switch self {
            case .connected(let port): "FT232R on \(port) · connected"
            case .adapterNotFound: "No adapter found"
            case .disconnected: "Adapter unplugged"
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

        // Drop DTR and RTS, and make sure no break is being sent.
        //
        // The Python version did this and the Swift one didn't, which is the
        // sort of difference that ends with the desk's handset clicking: the
        // box treats a line going low as the start of a byte. Nothing here
        // ever writes, and these three calls are the belt to that braces.
        var lines: Int32 = TIOCM_DTR | TIOCM_RTS
        _ = ioctl(fd, TIOCMBIC, &lines)
        _ = ioctl(fd, TIOCCBRK)

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
