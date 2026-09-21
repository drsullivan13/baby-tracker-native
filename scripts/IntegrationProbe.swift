import Foundation
import Darwin
import BabyTrackerDomain
import BabyTrackerPersistence

@main
struct IntegrationProbe {
    @MainActor
    static func main() async throws {
        setbuf(stdout, nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("babytracker-integration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urlA = directory.appendingPathComponent("a/store.sqlite"), urlB = directory.appendingPathComponent("b/store.sqlite")
        var storeA = try OperationStore(storeURL: urlA)
        var storeB = try OperationStore(storeURL: urlB)
        let family = UUID(), deviceA = UUID(), deviceB = UUID()
        let secret = Data(repeating: 0x24, count: 32)
        let a = NearbySync(testFamilyID: family, secret: secret, host: true, deviceID: deviceA, peerID: deviceB)
        let b = NearbySync(testFamilyID: family, secret: secret, host: false, deviceID: deviceB, peerID: deviceA)
        a.snapshotProvider = { try storeA.snapshotData() }
        b.snapshotProvider = { try storeB.snapshotData() }
        a.snapshotReceiver = { _ = try storeA.mergeSnapshot($0) }
        b.snapshotReceiver = { _ = try storeB.mergeSnapshot($0) }
        let bottle = Activity(kind: .feed, startedAt: Date(), feedMethod: .bottle, amountMl: 75, bottleMilkType: .formula)
        let timer = Activity(kind: .sleep, startedAt: Date().addingTimeInterval(-600), isRunning: true)
        _ = try storeA.append(action: .create, payload: .activity(bottle))
        _ = try storeB.append(action: .create, payload: .activity(timer))
        a.start(); b.start()
        defer { a.stop(); b.stop() }
        try await wait("initial persistent exchange") {
            try storeA.reducedDataset().activities.count == 2 && storeB.reducedDataset().activities.count == 2 && a.lastSync != nil && b.lastSync != nil
        }
        guard try storeA.reducedDataset() == storeB.reducedDataset() else { throw Failure.mismatch }
        print("PASS: two on-disk Core Data stores merge independent offline additions through authenticated transport")
        a.stop(); b.stop()
        var changeA = bottle; changeA.amountMl = 85
        var changeB = bottle; changeB.amountMl = 95
        _ = try storeA.append(action: .edit, payload: .activity(changeA))
        _ = try storeB.append(action: .edit, payload: .activity(changeB))
        var stop = timer; stop.isRunning = false; stop.endedAt = Date()
        _ = try storeA.append(action: .stopTimer, payload: .activity(stop))
        // Reopen the same stores before reconnecting, like an app restart.
        storeA = try OperationStore(storeURL: urlA)
        storeB = try OperationStore(storeURL: urlB)
        a.start(); b.start()
        try await wait("offline edits and remote timer stop") {
            let one = try storeA.reducedDataset(), two = try storeB.reducedDataset()
            return one == two && one.conflicts.count == 1 && one.activities[timer.id]?.isRunning == false
        }
        let conflict = try storeA.reducedDataset().conflicts[0]
        _ = try storeA.append(action: .resolveConflict, payload: .activity(changeA), resolves: conflict.operationIDs)
        a.requestSync()
        try await wait("conflict resolution") {
            let one = try storeA.reducedDataset(), two = try storeB.reducedDataset()
            return one == two && one.conflicts.isEmpty && one.activities[bottle.id]?.amountMl == 85
        }
        print("PASS: exact persistent reopen, concurrent edit retention/resolution, and stopping a timer from the other peer converge")
        let beforeA = try storeA.operations().count, beforeB = try storeB.operations().count
        a.requestSync(); b.requestSync()
        try await Task.sleep(for: .seconds(2))
        guard try storeA.operations().count == beforeA && storeB.operations().count == beforeB else { throw Failure.mismatch }
        print("PASS: repeated bidirectional full snapshots add zero duplicate operations")
    }
    @MainActor
    static func wait(_ name: String, until predicate: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if try predicate() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("FAIL: \(name)")
        throw Failure.timeout
    }
}
private enum Failure: Error { case mismatch, timeout }
