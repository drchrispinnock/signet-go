import Testing
@testable import Signet

/// Ledger's Bluetooth framing (the transport itself needs a device and is not tested here).
@Suite struct LedgerBLEFramingTests {
    @Test func framesFitTheMTUWithoutPadding() {
        let apdu = (0..<300).map { UInt8($0 & 0xff) }
        let frames = LedgerBLEFraming.frames(for: apdu, mtu: 100)
        #expect(frames.allSatisfy { $0.count <= 100 })
        #expect(frames[0].prefix(5) == [0x05, 0x00, 0x00, 0x01, 0x2c])
        #expect(frames[1].prefix(3) == [0x05, 0x00, 0x01])
        #expect(frames.last!.count < 100)   // no padding
        #expect(frames.count == 4)          // 95 + 97 + 97 + 11
    }

    @Test func reassemblesWhatItFramesAtAnyMTU() throws {
        let apdu = (0..<513).map { UInt8($0 % 251) }
        for mtu in [20, 23, 64, 128, 153] {
            var reassembler = LedgerBLEFraming.Reassembler()
            var result: [UInt8]?
            for frame in LedgerBLEFraming.frames(for: apdu, mtu: mtu) { result = try reassembler.add(frame) }
            #expect(result == apdu, "mtu \(mtu)")
        }
        // An empty APDU still makes one frame with its length.
        #expect(LedgerBLEFraming.frames(for: [], mtu: 20) == [[0x05, 0, 0, 0, 0]])
    }

    @Test func refusesOutOfOrderOrForeignFrames() {
        var reassembler = LedgerBLEFraming.Reassembler()
        #expect(throws: LedgerBLEFraming.Reassembler.FramingError.badHeader) { try reassembler.add([0x01, 0x01, 0x05]) }
        var second = LedgerBLEFraming.Reassembler()
        #expect(throws: LedgerBLEFraming.Reassembler.FramingError.outOfOrder(expected: 0, got: 1)) { try second.add([0x05, 0x00, 0x01, 0xaa]) }
    }

    @Test func readsTheMTUAnswer() {
        #expect(LedgerBLEFraming.mtu(fromResponse: [0x08, 0, 0, 0, 1, 153]) == 153)
        #expect(LedgerBLEFraming.mtu(fromResponse: [0x05, 0, 0]) == nil)
    }

    @Test func knowsTheBluetoothModels() {
        #expect(LedgerBLEModel.all.map(\.name) == ["Ledger Nano X", "Ledger Flex", "Ledger Stax"])
        #expect(LedgerBLEModel.all[0].service.uuidString.lowercased() == "13d63400-2c97-0004-0000-4c6564676572")
        #expect(LedgerDevice(id: "x", name: "", productID: LedgerBLEModel.all[0].productID).model == "Ledger Nano X")
    }
}
