import CoreBluetooth
import Foundation

/// Ledger's Bluetooth framing: the USB HID framing without the two-byte channel. Each write is
/// at most the negotiated MTU (no padding): tag 0x05, a two-byte sequence, and on the first
/// frame the two-byte APDU length. Pure, so the tests cover it.
enum LedgerBLEFraming {
    static let tag: UInt8 = 0x05
    /// The MTU request the device answers with its frame size (Ledger's BLE transport).
    static let mtuRequest: [UInt8] = [0x08, 0x00, 0x00, 0x00, 0x00]
    static let defaultMTU = 20

    static func frames(for apdu: [UInt8], mtu: Int) -> [[UInt8]] {
        let mtu = max(mtu, 8)
        var frames: [[UInt8]] = []
        var offset = 0
        var sequence: UInt16 = 0
        repeat {
            var frame = [tag, UInt8(sequence >> 8), UInt8(sequence & 0xff)]
            if sequence == 0 { frame += [UInt8(apdu.count >> 8), UInt8(apdu.count & 0xff)] }
            let chunk = apdu[offset ..< min(apdu.count, offset + mtu - frame.count)]
            frame += chunk
            frames.append(frame)
            offset += chunk.count
            sequence += 1
        } while offset < apdu.count
        return frames
    }

    /// The device's answer to `mtuRequest`: `08 00 00 00 01 <mtu>`.
    static func mtu(fromResponse bytes: [UInt8]) -> Int? {
        guard bytes.count >= 6, bytes[0] == 0x08 else { return nil }
        return Int(bytes[5])
    }

    /// Collects notifications until a whole response has arrived.
    struct Reassembler {
        enum FramingError: Error, Equatable { case badHeader, outOfOrder(expected: Int, got: Int) }
        private var expectedLength: Int?
        private var data: [UInt8] = []
        private var nextSequence = 0

        init() {}

        mutating func add(_ frame: [UInt8]) throws -> [UInt8]? {
            guard frame.count >= 3, frame[0] == tag else { throw FramingError.badHeader }
            let sequence = Int(frame[1]) << 8 | Int(frame[2])
            guard sequence == nextSequence else { throw FramingError.outOfOrder(expected: nextSequence, got: sequence) }
            var body: ArraySlice<UInt8>
            if sequence == 0 {
                guard frame.count >= 5 else { throw FramingError.badHeader }
                expectedLength = Int(frame[3]) << 8 | Int(frame[4])
                body = frame[5...]
            } else {
                body = frame[3...]
            }
            guard let expectedLength else { throw FramingError.badHeader }
            data += body.prefix(expectedLength - data.count)
            nextSequence += 1
            guard data.count >= expectedLength else { return nil }
            defer { self = Reassembler() }
            return data
        }
    }
}

/// Ledger models that speak Bluetooth, with the GATT UUIDs Ledger publishes for them
/// (@ledgerhq/devices). The USB product id's high byte stands in for `LedgerDevice.productID`
/// so its model names apply.
// CBUUID is immutable, so sharing these across threads is safe.
struct LedgerBLEModel: @unchecked Sendable {
    let name: String
    let productID: Int
    let service: CBUUID
    let notify: CBUUID
    let write: CBUUID
    let writeCommand: CBUUID

    init(name: String, productID: Int, prefix: String) {
        self.name = name
        self.productID = productID
        service = CBUUID(string: "13d63400-2c97-\(prefix)-0000-4c6564676572")
        notify = CBUUID(string: "13d63400-2c97-\(prefix)-0001-4c6564676572")
        write = CBUUID(string: "13d63400-2c97-\(prefix)-0002-4c6564676572")
        writeCommand = CBUUID(string: "13d63400-2c97-\(prefix)-0003-4c6564676572")
    }

    static let all = [
        LedgerBLEModel(name: "Ledger Nano X", productID: 0x4000, prefix: "0004"),
        LedgerBLEModel(name: "Ledger Flex", productID: 0x7000, prefix: "3004"),
        LedgerBLEModel(name: "Ledger Stax", productID: 0x6000, prefix: "6004"),
    ]

    static func model(for service: CBUUID) -> LedgerBLEModel? { all.first { $0.service == service } }
}

/// Stands in for upstream's IOKit `LedgerHID` on iOS: the same `devices()` and `exchange`
/// that the bridge's `NativeLedgerTransport` calls, over Bluetooth Low Energy (Nano X, Flex,
/// Stax; iPhones cannot reach a Ledger over USB HID). Scanning starts on the first `devices()`
/// call. One exchange per device at a time; an exchange that times out or fails disconnects the
/// device, so its late notifications can never answer a later exchange (S22). Device ids are
/// the peripherals' CoreBluetooth identifiers. Not yet exercised against a real device.
final class LedgerHID: NSObject, @unchecked Sendable {
    enum BLEError: LocalizedError {
        case bluetoothOff, unauthorized, noSuchDevice, busy, notReady, timeout, framing, disconnected
        var errorDescription: String? {
            switch self {
            case .bluetoothOff: "Bluetooth is off."
            case .unauthorized: "Signet Go is not allowed to use Bluetooth. Allow it in Settings."
            case .noSuchDevice: "The Ledger is no longer in range."
            case .busy: "The Ledger is busy with another request."
            case .notReady: "The Ledger did not finish connecting."
            case .timeout: "The Ledger did not answer in time."
            case .framing: "The Ledger's answer could not be read."
            case .disconnected: "The Ledger disconnected."
            }
        }
    }

    static let shared = LedgerHID()

    private let queue = DispatchQueue(label: "LedgerHID.ble")
    private var central: CBCentralManager?

    /// Everything about one peripheral; touched on `queue` only.
    private final class Link {
        let peripheral: CBPeripheral
        let model: LedgerBLEModel
        var name: String
        var lastSeen = Date()
        var writeCharacteristic: CBCharacteristic?
        var notifyReady = false
        var mtu: Int?
        var onReady: [(Result<Void, Error>) -> Void] = []
        var pending: Pending?
        init(peripheral: CBPeripheral, model: LedgerBLEModel, name: String) {
            self.peripheral = peripheral; self.model = model; self.name = name
        }
    }

    private struct Pending {
        let id = UUID()
        var reassembler = LedgerBLEFraming.Reassembler()
        var awaitingMTU: Bool
        let complete: (Result<[UInt8], Error>) -> Void
    }

    private var links: [UUID: Link] = [:]

    override init() { super.init() }

    // MARK: Upstream's interface

    /// Ledgers seen advertising in the last half minute, or connected.
    func devices() -> [LedgerDevice] {
        queue.sync {
            startScanning()
            let fresh = Date().addingTimeInterval(-30)
            return links.values
                .filter { $0.peripheral.state == .connected || $0.lastSeen > fresh }
                .map { LedgerDevice(id: $0.peripheral.identifier.uuidString, name: $0.name, productID: $0.model.productID) }
                .sorted { $0.name < $1.name }
        }
    }

    func exchange(deviceID: String, apdu: [UInt8], timeout: TimeInterval, completionQueue: DispatchQueue, completion: @escaping @Sendable (Result<[UInt8], Error>) -> Void) {
        let deliver: (Result<[UInt8], Error>) -> Void = { result in completionQueue.async { completion(result) } }
        queue.async { [self] in
            guard let central, central.state == .poweredOn else { return deliver(.failure(stateError)) }
            guard let uuid = UUID(uuidString: deviceID), let link = links[uuid] else { return deliver(.failure(BLEError.noSuchDevice)) }
            guard link.pending == nil else { return deliver(.failure(BLEError.busy)) }
            let deadline = DispatchTime.now() + timeout
            ready(link) { [self] result in
                if case .failure(let error) = result { return deliver(.failure(error)) }
                let pending = Pending(awaitingMTU: false, complete: deliver)
                let id = pending.id
                link.pending = pending
                write(LedgerBLEFraming.frames(for: apdu, mtu: link.mtu ?? LedgerBLEFraming.defaultMTU), to: link)
                queue.asyncAfter(deadline: deadline) { [self] in
                    guard let current = link.pending, current.id == id else { return }
                    fail(link, BLEError.timeout)
                }
            }
        }
    }

    // MARK: Connection

    private var stateError: BLEError {
        switch central?.state {
        case .unauthorized: .unauthorized
        case .poweredOff: .bluetoothOff
        default: .notReady
        }
    }

    private func startScanning() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        } else if central?.state == .poweredOn, central?.isScanning == false {
            central?.scanForPeripherals(withServices: LedgerBLEModel.all.map(\.service))
        }
    }

    /// Connects, finds the characteristics, turns on notifications and agrees the MTU, then
    /// calls `done` (at once when the link is already up).
    private func ready(_ link: Link, done: @escaping (Result<Void, Error>) -> Void) {
        if link.peripheral.state == .connected, link.notifyReady, link.writeCharacteristic != nil, link.mtu != nil {
            return done(.success(()))
        }
        link.onReady.append(done)
        guard link.onReady.count == 1 else { return }
        if link.peripheral.state == .connected {
            link.peripheral.discoverServices([link.model.service])
        } else {
            central?.connect(link.peripheral)
        }
        queue.asyncAfter(deadline: .now() + 20) { [self] in
            guard !link.onReady.isEmpty else { return }
            finishReady(link, .failure(BLEError.notReady))
            central?.cancelPeripheralConnection(link.peripheral)
        }
    }

    private func finishReady(_ link: Link, _ result: Result<Void, Error>) {
        let waiting = link.onReady
        link.onReady = []
        waiting.forEach { $0(result) }
    }

    private func write(_ frames: [[UInt8]], to link: Link) {
        guard let characteristic = link.writeCharacteristic else { return fail(link, BLEError.notReady) }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        for frame in frames {
            link.peripheral.writeValue(Data(frame), for: characteristic, type: type)
        }
    }

    /// Ends the exchange in flight with `error` and drops the connection, so nothing late from
    /// the device can answer a later exchange.
    private func fail(_ link: Link, _ error: Error) {
        let pending = link.pending
        link.pending = nil
        link.mtu = nil
        link.notifyReady = false
        central?.cancelPeripheralConnection(link.peripheral)
        pending?.complete(.failure(error))
    }
}

extension LedgerHID: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: LedgerBLEModel.all.map(\.service))
            // Ledgers already connected to this phone (by Ledger Live, say) do not advertise.
            for peripheral in central.retrieveConnectedPeripherals(withServices: LedgerBLEModel.all.map(\.service)) {
                remember(peripheral, services: LedgerBLEModel.all.map(\.service))
            }
        } else {
            for link in links.values {
                if link.pending != nil { fail(link, stateError) }
                finishReady(link, .failure(stateError))
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        remember(peripheral, services: services, name: advertisementData[CBAdvertisementDataLocalNameKey] as? String)
    }

    private func remember(_ peripheral: CBPeripheral, services: [CBUUID], name: String? = nil) {
        if let link = links[peripheral.identifier] {
            link.lastSeen = Date()
            if let name { link.name = name }
            return
        }
        guard let model = services.lazy.compactMap(LedgerBLEModel.model(for:)).first else { return }
        peripheral.delegate = self
        links[peripheral.identifier] = Link(peripheral: peripheral, model: model, name: name ?? peripheral.name ?? model.name)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let link = links[peripheral.identifier] else { return }
        peripheral.discoverServices([link.model.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let link = links[peripheral.identifier] else { return }
        finishReady(link, .failure(error ?? BLEError.notReady))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard let link = links[peripheral.identifier] else { return }
        link.notifyReady = false
        link.mtu = nil
        link.writeCharacteristic = nil
        finishReady(link, .failure(BLEError.disconnected))
        if let pending = link.pending {
            link.pending = nil
            pending.complete(.failure(BLEError.disconnected))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let link = links[peripheral.identifier], let service = peripheral.services?.first(where: { $0.uuid == link.model.service }) else {
            if let link = links[peripheral.identifier] { finishReady(link, .failure(error ?? BLEError.notReady)) }
            return
        }
        peripheral.discoverCharacteristics([link.model.notify, link.model.write, link.model.writeCommand], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let link = links[peripheral.identifier], let characteristics = service.characteristics else { return }
        // Prefer the write-without-response characteristic when the device has one.
        link.writeCharacteristic = characteristics.first { $0.uuid == link.model.writeCommand } ?? characteristics.first { $0.uuid == link.model.write }
        guard let notify = characteristics.first(where: { $0.uuid == link.model.notify }), link.writeCharacteristic != nil else {
            return finishReady(link, .failure(BLEError.notReady))
        }
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let link = links[peripheral.identifier] else { return }
        if let error { return finishReady(link, .failure(error)) }
        link.notifyReady = true
        // Agree the frame size before the first APDU.
        link.pending = Pending(awaitingMTU: true) { _ in }
        if let characteristic = link.writeCharacteristic {
            peripheral.writeValue(Data(LedgerBLEFraming.mtuRequest), for: characteristic, type: characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let link = links[peripheral.identifier], let value = characteristic.value else { return }
        let bytes = [UInt8](value)
        guard var pending = link.pending else { return }   // nothing asked: a stale notification, dropped
        if pending.awaitingMTU {
            link.pending = nil
            link.mtu = LedgerBLEFraming.mtu(fromResponse: bytes) ?? LedgerBLEFraming.defaultMTU
            return finishReady(link, .success(()))
        }
        do {
            if let response = try pending.reassembler.add(bytes) {
                link.pending = nil
                pending.complete(.success(response))
            } else {
                link.pending = pending
            }
        } catch {
            fail(link, BLEError.framing)
        }
    }
}
