import CoreBluetooth
import DeskCore
import Foundation
import Observation

/// Looks for the desk's Bluetooth adapter.
///
/// The F port exists for a dongle - that's what Jiecang's support says it's
/// for - so a dongle in it should be speaking the same protocol we spent a
/// week decoding, just over the air instead of down a wire. Over the air
/// there's no shared ground, which is the thing that makes the handset click.
///
/// This is the first half: find out what's there and what it offers. Reading
/// heights from it comes after, and only if what it offers makes sense.
@MainActor
@Observable
final class DeskBluetooth: NSObject {
    struct Found: Identifiable {
        let id: UUID
        var name: String
        var rssi: Int
        var services: [String]
        var manufacturer: String?
        /// Set once we've connected and asked what it can do.
        var detail: [String] = []
    }

    private(set) var isScanning = false
    private(set) var state = "not started"
    private(set) var found: [Found] = []
    /// True while a dongle is connected and subscribed to the height stream.
    private(set) var isListening = false
    /// Heights, decoded by the same parser the wire uses: the dongle hands
    /// over the box's own frames, untouched.
    var onHeight: ((Double, Date) -> Void)?
    /// Remembered, so the next launch connects rather than searches.
    var rememberDevice: ((UUID) -> Void)?
    /// The one to reconnect to, from last time.
    var knownDevice: UUID?
    /// Called once the height stream is live and the box can be spoken to.
    var onReady: (() -> Void)?

    private var parser = FrameParser()
    private var listening: CBPeripheral?

    private var central: CBCentralManager?
    private var connecting: CBPeripheral?
    private let log = BluetoothLog()

    /// Scans for everything advertising nearby. Nothing is filtered by
    /// service, because we don't yet know what the adapter advertises - and
    /// a dongle that advertises nothing of ours is itself an answer.
    /// Opens the height stream: straight to the dongle we know, or a scan
    /// to find it the first time.
    func listen() {
        interrogateDeskWhenFound = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        connectKnownOrScan()
    }

    private func connectKnownOrScan() {
        guard let central else { return }
        if let knownDevice,
           let peripheral = central.retrievePeripherals(withIdentifiers: [knownDevice]).first {
            log.note("reconnecting to the dongle we know")
            listening = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
            return
        }
        start()
    }

    func scan() {
        found = []
        log.note("scan requested")
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            start()
        }
    }

    /// Sends one frame to the box, through the dongle's command channel.
    ///
    /// The first thing this app has ever transmitted. Everything up to now
    /// was receive-only by construction, because a stray edge on the wire
    /// made the handset click - but the dongle's whole purpose is two-way
    /// traffic, and it is the desk's own fitted accessory doing the talking.
    ///
    /// Frames are built, not typed: `F1 F1 cmd len data… checksum 7E`, with
    /// the checksum the sum of everything from cmd to the last data byte.
    /// A frame assembled wrongly is a frame whose meaning nobody knows.
    func send(command: UInt8) {
        let data: [UInt8] = []
        guard let peripheral = listening,
              let characteristic = peripheral.services?
                .first(where: { $0.uuid == CBUUID(string: "FE60") })?
                .characteristics?
                .first(where: { $0.uuid == CBUUID(string: "FE61") })
        else {
            log.note("send: not connected, or no FE61 to write to")
            return
        }
        let body: [UInt8] = [command, UInt8(data.count)] + data
        var total = 0
        for byte in body { total += Int(byte) }
        let checksum = UInt8(total & 0xFF)
        let frame: [UInt8] = [0xF1, 0xF1] + body + [checksum, 0x7E]
        let hex = frame.map { String(format: "%02X", $0) }.joined(separator: " ")
        log.note("SENDING → \(hex)")
        peripheral.writeValue(Data(frame), for: characteristic, type: .withResponse)
    }

    /// Stops listening and lets go of the dongle.
    func disconnect() {
        if let listening { central?.cancelPeripheralConnection(listening) }
        listening = nil
        isListening = false
        log.note("disconnected on purpose")
    }

    /// Set when the scan should go straight on to asking the desk what it
    /// offers, rather than waiting to be told which one it is.
    var interrogateDeskWhenFound = false

    func stop() {
        central?.stopScan()
        isScanning = false
        log.note("scan stopped — \(found.count) device(s)")
        guard interrogateDeskWhenFound,
              let desk = found.first(where: { $0.name.lowercased().contains("desk") })
        else { return }
        log.note("the desk looks like \(desk.name) — asking it what it has")
        interrogate(desk)
    }

    /// Connects to one and writes down every service and characteristic it
    /// has. This is the part that says whether we can use it.
    func interrogate(_ device: Found) {
        guard let central, let peripheral = central.retrievePeripherals(withIdentifiers: [device.id]).first
        else { return }
        log.note("connecting to \(device.name)")
        connecting = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    private func start() {
        isScanning = true
        state = "scanning"
        central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        log.note("scanning")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            if isScanning { stop() }
        }
    }
}

// The manager is created on the main queue, so every callback arrives on the
// main actor. A @preconcurrency conformance is how a main-actor class
// satisfies CoreBluetooth's older, isolation-free delegate protocols.
extension DeskBluetooth: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = "ready"
            if interrogateDeskWhenFound, knownDevice != nil {
                connectKnownOrScan()
            } else {
                start()
            }
        case .unauthorized:
            state = "Bluetooth permission refused — System Settings › Privacy & Security › Bluetooth"
        case .poweredOff:
            state = "Bluetooth is switched off"
        case .unsupported:
            state = "no Bluetooth on this Mac"
        default:
            state = "starting up"
        }
        log.note("state: \(state)")
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi: NSNumber
    ) {
        let id = peripheral.identifier
        guard !found.contains(where: { $0.id == id }) else { return }
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "(unnamed)"
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
            .map(\.uuidString) ?? []
        let manufacturer = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?
            .map { String(format: "%02X", $0) }.joined()

        found.append(Found(
            id: id, name: name, rssi: rssi.intValue, services: services, manufacturer: manufacturer
        ))
        log.note(
            "found \(name)  rssi \(rssi.intValue)"
            + (services.isEmpty ? "" : "  services \(services.joined(separator: ", "))")
            + (manufacturer.map { "  mfg \($0)" } ?? "")
            + "  id \(id)"
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.note("connected to \(peripheral.name ?? "(unnamed)") — asking what it has")
        listening = peripheral
        state = "connected to \(peripheral.name ?? "the dongle")"
        rememberDevice?(peripheral.identifier)
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        log.note("connect failed: \(error?.localizedDescription ?? "no reason given")")
    }

    /// A dongle that hangs up looks exactly like a dongle with nothing to
    /// say, which is why this is worth writing down.
    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        isListening = false
        state = "reconnecting"
        log.note("DISCONNECTED: \(error?.localizedDescription ?? "it hung up") — reconnecting")
        central.connect(peripheral)
    }
}

extension DeskBluetooth: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            log.note("  service \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        let id = peripheral.identifier
        for characteristic in service.characteristics ?? [] {
            var can: [String] = []
            let properties = characteristic.properties
            if properties.contains(.read) { can.append("read") }
            if properties.contains(.write) { can.append("write") }
            if properties.contains(.writeWithoutResponse) { can.append("write-no-reply") }
            if properties.contains(.notify) { can.append("notify") }
            if properties.contains(.indicate) { can.append("indicate") }

            let line = "    characteristic \(characteristic.uuid.uuidString)  [\(can.joined(separator: ", "))]"
            log.note(line)
            if let index = found.firstIndex(where: { $0.id == id }) {
                found[index].detail.append(line)
            }
            // Anything that notifies is a candidate for the height stream.
            if properties.contains(.notify) { peripheral.setNotifyValue(true, for: characteristic) }
            // And anything readable is worth asking once: the device
            // information service says who actually made this thing.
            if properties.contains(.read) { peripheral.readValue(for: characteristic) }
        }
    }

    /// Whether the subscription actually took. A notify characteristic that
    /// silently refuses is the other way to get silence.
    func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        log.note(
            "    \(characteristic.uuid.uuidString) notifications "
            + (characteristic.isNotifying ? "ON" : "off")
            + (error.map { " — \($0.localizedDescription)" } ?? "")
        )
        // FE62 is the one that carries the box's frames.
        if characteristic.uuid == CBUUID(string: "FE62"), characteristic.isNotifying {
            isListening = true
            state = "listening over Bluetooth"
            onReady?()
        }
    }

    /// Whether the box accepted what we sent.
    func peripheral(
        _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        log.note("    write to \(characteristic.uuid.uuidString): "
                 + (error.map { "refused — \($0.localizedDescription)" } ?? "accepted"))
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard let data = characteristic.value else { return }

        // The dongle relays the box's own frames, so the parser that reads
        // the wire reads this too, byte for byte.
        if characteristic.uuid == CBUUID(string: "FE62") {
            let now = Date()
            for frame in parser.feed([UInt8](data)) {
                if let height = frame.height { onHeight?(height, now) }
            }
        }

        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        // Device-information values are text; the vendor service is bytes.
        let text = String(data: data, encoding: .utf8).flatMap { readable in
            readable.allSatisfy { $0.isASCII && (!$0.isWhitespace || $0 == " ") && !$0.isNewline }
                ? readable : nil
        }
        log.note("    \(characteristic.uuid.uuidString) → \(hex)" + (text.map { "   \"\($0)\"" } ?? ""))
    }
}

/// The scan's own log, so a run can be read afterwards rather than watched.
final class BluetoothLog: @unchecked Sendable {
    static let url = Paths.support.appending(path: "bluetooth.log")
    private let queue = DispatchQueue(label: "desk.ble.log")

    func note(_ text: String) {
        let line = SerialLog.event(text, at: Date())
        queue.async {
            try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: Self.url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: Self.url)
            }
        }
    }
}
