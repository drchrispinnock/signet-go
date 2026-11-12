import Foundation

#if !canImport(IOKit)
/// iOS has no USB HID for apps. Upstream's `LedgerHID.swift` still supplies `LedgerFraming` and
/// `LedgerDevice`; this stands in for its IOKit class until Ledger over Bluetooth arrives
/// (Nano X, Flex, Stax): no devices, and every exchange fails.
final class LedgerHID: @unchecked Sendable {
    enum HIDError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Ledger is not available on iOS yet." }
    }

    static let shared = LedgerHID()

    func devices() -> [LedgerDevice] { [] }

    func exchange(deviceID: String, apdu: [UInt8], timeout: TimeInterval, completionQueue: DispatchQueue, completion: @escaping @Sendable (Result<[UInt8], Error>) -> Void) {
        completionQueue.async { completion(.failure(HIDError.unavailable)) }
    }
}
#endif
