import Foundation
import Darwin

/// Compiled separately with TRANSPORT_TESTING; never included in the iOS app.
@main
struct TransportProbe {
    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        let family = UUID()
        let secret = Data(repeating: 0x42, count: 32) // Synthetic test credential only.
        let firstID = UUID(), secondID = UUID()
        let first = NearbySync(testFamilyID: family, secret: secret, host: true, deviceID: firstID)
        let second = NearbySync(testFamilyID: family, secret: secret, host: false, deviceID: secondID)
        let payloadA = Data(repeating: 0x41, count: 200_000)
        let payloadB = Data(repeating: 0x42, count: 300_000)
        var firstReceives = 0
        var secondReceives = 0
        first.snapshotProvider = { payloadA }
        second.snapshotProvider = { payloadB }
        first.snapshotReceiver = { value in
            guard value == payloadB else { throw ProbeFailure.mismatch }
            firstReceives += 1
        }
        second.snapshotReceiver = { value in
            guard value == payloadA else { throw ProbeFailure.mismatch }
            secondReceives += 1
        }
        first.start(); second.start()
        defer { first.stop(); second.stop() }
        try await wait("pairing handshake", first: first, second: second) { first.pendingConfirmation && second.pendingConfirmation }
        guard first.confirmationCode == second.confirmationCode else { throw ProbeFailure.mismatch }
        guard firstReceives == 0 && secondReceives == 0 else { throw ProbeFailure.prematureData }
        first.confirmPairing()
        try await Task.sleep(for: .milliseconds(300))
        guard firstReceives == 0 && secondReceives == 0 else { throw ProbeFailure.prematureData }
        second.confirmPairing()
        try await wait("bidirectional chunked sync", first: first, second: second) { first.lastSync != nil && second.lastSync != nil }
        guard firstReceives == 1 && secondReceives == 1 else { throw ProbeFailure.mismatch }
        print("PASS: encrypted pairing, two-sided consent, 200/300 KB chunked bidirectional transfer and durable receiver ACK")
        first.stop(); second.stop()
        first.start(); second.start()
        try await wait("reconnect", first: first, second: second) { firstReceives == 2 && secondReceives == 2 }
        print("PASS: pinned paired devices reconnect without confirmation")
        first.testSendUnsupportedVersion()
        try await wait("incompatible version rejection", first: first, second: second) { second.errorMessage != nil }
        guard firstReceives == 2 && secondReceives == 2 else { throw ProbeFailure.mismatch }
        print("PASS: incompatible wire protocol rejected without importing data")
        first.stop(); second.stop()
        first.errorMessage = nil; second.errorMessage = nil
        first.start(); second.start()
        try await wait("reconnect after rejection", first: first, second: second) { firstReceives == 3 && secondReceives == 3 }
        // A failed durable write must never receive an acknowledgement.
        second.snapshotReceiver = { _ in throw ProbeFailure.diskFailure }
        let prior = first.lastSync
        first.requestSync()
        try await wait("receiver failure", first: first, second: second) { second.errorMessage != nil }
        guard first.lastSync == prior else { throw ProbeFailure.falseAcknowledgement }
        print("PASS: failed durable receiver prevents successful sync acknowledgement")
        first.stop(); second.stop()
        let intruder = NearbySync(testFamilyID: family, secret: Data(repeating: 0x99, count: 32), host: false)
        var intruderReceives = 0
        intruder.snapshotProvider = { payloadB }
        intruder.snapshotReceiver = { _ in intruderReceives += 1 }
        first.errorMessage = nil
        first.start(); intruder.start()
        defer { intruder.stop() }
        try await wait("wrong secret rejected", first: first, second: intruder) { first.errorMessage != nil || intruder.errorMessage != nil }
        guard intruderReceives == 0 && !intruder.pendingConfirmation else { throw ProbeFailure.prematureData }
        print("PASS: wrong pairing secret cannot establish authenticated data exchange")
    }
    @MainActor
    static func wait(_ name: String, first: NearbySync, second: NearbySync, until predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(35)
        while !predicate() && Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        guard predicate() else {
            print("FAIL: \(name); first=\(first.status), second=\(second.status); errors=\(first.errorMessage ?? "none") / \(second.errorMessage ?? "none")")
            throw ProbeFailure.timeout
        }
    }
}
enum ProbeFailure: Error { case timeout, mismatch, prematureData, diskFailure, falseAcknowledgement }
