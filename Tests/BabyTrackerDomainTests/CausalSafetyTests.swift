import XCTest
import BabyTrackerDomain
import BabyTrackerPersistence

final class CausalSafetyTests: XCTestCase {
    func testDeleteStillWinsAfterItsHeadIsEditedAndAnotherBranchArrives() throws {
        let a = try OperationStore(inMemory: true), b = try OperationStore(inMemory: true)
        let value = Activity(kind: .diaper, startedAt: Date(timeIntervalSince1970: 100), diaperKind: .wet)
        _ = try a.append(action: .create, payload: .activity(value))
        _ = try b.mergeSnapshot(a.snapshotData())
        var deleted = value; deleted.deleted = true
        _ = try a.append(action: .delete, payload: .activity(deleted))
        var staleView = value; staleView.diaperKind = .both
        _ = try a.append(action: .edit, payload: .activity(staleView))
        for _ in 0..<8 { _ = try b.append(action: .edit, payload: .activity(value)) }
        _ = try a.mergeSnapshot(b.snapshotData())
        _ = try b.mergeSnapshot(a.snapshotData())
        XCTAssertTrue(try XCTUnwrap(a.reducedDataset().activities[value.id]).deleted)
        XCTAssertEqual(try a.reducedDataset(), try b.reducedDataset())
        let conflict = try XCTUnwrap(a.reducedDataset().conflicts.first)
        let effectiveDeleted = try XCTUnwrap(conflict.versions.first { payload in
            if case .activity(let entry) = payload { return entry.deleted && entry.diaperKind == .both }
            return false
        })
        _ = try a.append(action: .resolveConflict, payload: effectiveDeleted, resolves: conflict.operationIDs)
        XCTAssertTrue(try XCTUnwrap(a.reducedDataset().activities[value.id]).deleted)
        XCTAssertTrue(try a.reducedDataset().conflicts.isEmpty)

    }
    func testStopStillWinsWhenItsMetadataIsEditedBeforeConcurrentRunningBranchArrives() throws {
        let a = try OperationStore(inMemory: true), b = try OperationStore(inMemory: true)
        let value = Activity(kind: .sleep, startedAt: Date(timeIntervalSince1970: 100), isRunning: true)
        _ = try a.append(action: .create, payload: .activity(value))
        _ = try b.mergeSnapshot(a.snapshotData())
        var stopped = value; stopped.isRunning = false; stopped.endedAt = Date(timeIntervalSince1970: 200)
        _ = try a.append(action: .stopTimer, payload: .activity(stopped))
        stopped.startedAt = Date(timeIntervalSince1970: 90)
        _ = try a.append(action: .edit, payload: .activity(stopped))
        for _ in 0..<8 { _ = try b.append(action: .edit, payload: .activity(value)) }
        _ = try a.mergeSnapshot(b.snapshotData())
        let result = try XCTUnwrap(a.reducedDataset().activities[value.id])
        XCTAssertFalse(result.isRunning)
        XCTAssertEqual(result.endedAt, stopped.endedAt)
    }
}
