import XCTest
import BabyTrackerDomain

final class ReducerTests: XCTestCase {
    private let deviceA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let deviceB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    func testMergeIsDeterministicAcrossOrderAndDuplicates() throws {
        let first = Activity(
            id: UUID(), kind: .feed, startedAt: Date(timeIntervalSince1970: 100),
            feedMethod: .bottle
        )
        let create = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: first)
        var edited = first
        edited.amountMl = 90
        edited.feedMethod = .bottle
        let edit = operation(id: uuid(2), device: deviceA, clock: 2, base: create.id, action: .edit, activity: edited)

        let expected = try OperationReducer.replay([create, edit])
        for input in [[edit, create], [create, edit, edit], [edit, create, create]] {
            XCTAssertEqual(try OperationReducer.replay(input), expected)
        }
        XCTAssertEqual(expected.activities[first.id]?.amountMl, 90)
    }

    func testDeleteWinsOverEditUntilExplicitRestore() throws {
        let initial = Activity(id: UUID(), kind: .diaper, startedAt: Date(), diaperKind: .wet)
        let create = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: initial)
        var deleted = initial
        deleted.deleted = true
        let deletion = operation(id: uuid(2), device: deviceA, clock: 2, base: create.id, action: .delete, activity: deleted)
        var edited = initial
        edited.diaperKind = .dirty
        let edit = operation(id: uuid(3), device: deviceB, clock: 9, base: create.id, action: .edit, activity: edited)

        let deletedState = try OperationReducer.replay([edit, deletion, create])
        XCTAssertEqual(deletedState.activities[initial.id]?.deleted, true)

        edited.deleted = false
        let restore = operation(id: uuid(4), device: deviceA, clock: 3, base: deletion.id, action: .restore, activity: edited)
        let restored = try OperationReducer.replay([edit, restore, deletion, create])
        XCTAssertEqual(restored.activities[initial.id]?.deleted, false)
    }

    func testSequentialDeleteRestoreDeleteEndsDeleted() throws {
        let initial = Activity(id: UUID(), kind: .diaper, startedAt: Date(), diaperKind: .wet)
        let create = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: initial)
        var deleted = initial
        deleted.deleted = true
        let firstDelete = operation(
            id: uuid(2), device: deviceA, clock: 2, base: create.id,
            action: .delete, activity: deleted
        )
        var restored = initial
        restored.deleted = false
        let restore = operation(
            id: uuid(3), device: deviceA, clock: 3, base: firstDelete.id,
            action: .restore, activity: restored
        )
        let finalDelete = operation(
            id: uuid(4), device: deviceA, clock: 4, base: restore.id,
            action: .delete, activity: deleted
        )

        let result = try OperationReducer.replay([restore, create, finalDelete, firstDelete])
        XCTAssertTrue(try XCTUnwrap(result.activities[initial.id]).deleted)
        XCTAssertEqual(result.revisions[initial.id], finalDelete.id)
        XCTAssertTrue(result.conflicts.isEmpty)
    }

    func testConcurrentRestoreCannotResurrectDeleteItDidNotObserve() throws {
        let initial = Activity(id: UUID(), kind: .diaper, startedAt: Date(), diaperKind: .wet)
        let create = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: initial)
        var deleted = initial
        deleted.deleted = true
        let deletion = operation(
            id: uuid(2), device: deviceA, clock: 2, base: create.id,
            action: .delete, activity: deleted
        )
        let restore = operation(
            id: uuid(3), device: deviceB, clock: 99, base: create.id,
            action: .restore, activity: initial
        )

        let result = try OperationReducer.replay([restore, deletion, create])
        XCTAssertTrue(try XCTUnwrap(result.activities[initial.id]).deleted)
        XCTAssertEqual(result.conflicts.count, 1)
    }

    func testConcurrentEditsRetainConflictAndResolutionClearsIt() throws {
        let initial = Activity(id: UUID(), kind: .feed, startedAt: Date(), feedMethod: .breast, feedSide: .left)
        let create = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: initial)
        var left = initial
        left.feedSide = .left
        var right = initial
        right.feedSide = .right
        let editA = operation(id: uuid(2), device: deviceA, clock: 2, base: create.id, action: .edit, activity: left)
        let editB = operation(id: uuid(3), device: deviceB, clock: 2, base: create.id, action: .edit, activity: right)
        let conflicted = try OperationReducer.replay([editB, create, editA])
        XCTAssertEqual(conflicted.conflicts.count, 1)
        XCTAssertEqual(conflicted.activities[initial.id]?.feedSide, .right)

        let resolution = BabyTrackerDomain.Operation(
            id: uuid(4), entityID: initial.id, authorDeviceID: deviceA,
            lamport: 3, parentRevisions: [editA.id, editB.id],
            baseRevision: editB.id, action: .resolveConflict,
            payload: .activity(left), resolvesOperationIDs: [editA.id, editB.id]
        )
        XCTAssertTrue(try OperationReducer.replay([editA, resolution, create, editB]).conflicts.isEmpty)
    }

    func testConcurrentStopsConvergeToOneStoppedTimer() throws {
        let timer = Activity(
            id: UUID(), kind: .sleep, startedAt: Date(timeIntervalSince1970: 100),
            isRunning: true
        )
        let create = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: timer)
        var early = timer
        early.endedAt = Date(timeIntervalSince1970: 200)
        early.isRunning = false
        var late = timer
        late.endedAt = Date(timeIntervalSince1970: 220)
        late.isRunning = false
        let stopA = operation(id: uuid(2), device: deviceA, clock: 2, base: create.id, action: .stopTimer, activity: early)
        let stopB = operation(id: uuid(3), device: deviceB, clock: 2, base: create.id, action: .stopTimer, activity: late)
        let result = try OperationReducer.replay([stopB, create, stopA])
        XCTAssertEqual(result.activities.count, 1)
        XCTAssertEqual(result.activities[timer.id]?.endedAt, late.endedAt)
        XCTAssertEqual(result.activities[timer.id]?.isRunning, false)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(Set(result.conflicts[0].operationIDs), Set([stopA.id, stopB.id]))
    }

    func testConcurrentStaleEditCannotRestartStoppedTimer() throws {
        let timer = Activity(
            id: UUID(), kind: .sleep, startedAt: Date(timeIntervalSince1970: 100),
            isRunning: true
        )
        let create = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: timer)
        var stopped = timer
        stopped.endedAt = Date(timeIntervalSince1970: 200)
        stopped.isRunning = false
        let stop = operation(
            id: uuid(2), device: deviceA, clock: 2, base: create.id,
            action: .stopTimer, activity: stopped
        )
        var staleEdit = timer
        staleEdit.startedAt.addTimeInterval(5)
        let edit = operation(
            id: uuid(3), device: deviceB, clock: 50, base: create.id,
            action: .edit, activity: staleEdit
        )

        let result = try OperationReducer.replay([edit, stop, create])
        let value = try XCTUnwrap(result.activities[timer.id])
        XCTAssertFalse(value.isRunning)
        XCTAssertEqual(value.endedAt, stopped.endedAt)
        XCTAssertEqual(result.conflicts.count, 1)
    }

    func testResolutionSupersedesAcknowledgedHeadsButRetainsUnresolvedVariant() throws {
        let initial = Activity(
            id: UUID(), kind: .feed, startedAt: Date(),
            feedMethod: .breast, feedSide: .left
        )
        let create = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: initial)
        var left = initial
        left.feedSide = .left
        var right = initial
        right.feedSide = .right
        var both = initial
        both.feedSide = .both
        let editA = operation(id: uuid(2), device: deviceA, clock: 2, base: create.id, action: .edit, activity: left)
        let editB = operation(id: uuid(3), device: deviceB, clock: 2, base: create.id, action: .edit, activity: right)
        let editC = operation(id: uuid(4), device: uuid(9), clock: 2, base: create.id, action: .edit, activity: both)
        let resolution = BabyTrackerDomain.Operation(
            id: uuid(5), entityID: initial.id, authorDeviceID: deviceA,
            lamport: 3, parentRevisions: [editA.id, editB.id],
            baseRevision: editB.id, action: .resolveConflict,
            payload: .activity(left), resolvesOperationIDs: [editA.id, editB.id]
        )

        let result = try OperationReducer.replay([editC, resolution, editA, create, editB])
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(
            Set(result.conflicts[0].operationIDs),
            Set([resolution.id, editC.id])
        )
    }

    func testOperationIDCollisionAndProtocolVersionAreRejected() throws {
        let activity = Activity(id: UUID(), kind: .sleep, startedAt: Date())
        let first = operation(id: uuid(1), device: deviceA, clock: 1, action: .create, activity: activity)
        var changed = activity
        changed.startedAt.addTimeInterval(10)
        let collision = operation(id: first.id, device: deviceB, clock: 2, action: .edit, activity: changed)
        XCTAssertThrowsError(try OperationReducer.validatedUnion([first], [collision]))

        let invalid = BabyTrackerDomain.Operation(
            entityID: activity.id, authorDeviceID: deviceA, lamport: 1,
            schemaVersion: 2, action: .create, payload: .activity(activity)
        )
        XCTAssertThrowsError(try OperationReducer.replay([invalid]))
        let data = #"{"schemaVersion":2,"operations":[]}"#.data(using: .utf8)!
        XCTAssertThrowsError(try SnapshotCodec.decode(data))
    }

    func testSnapshotRoundTripPreservesExactDateBits() throws {
        let activity = Activity(
            id: UUID(), kind: .diaper,
            startedAt: Date(timeIntervalSinceReferenceDate: 123_456.123_456_789),
            diaperKind: .wet
        )
        let value = operation(
            id: uuid(1), device: deviceA, clock: 1,
            action: .create, activity: activity
        )
        let decoded = try XCTUnwrap(SnapshotCodec.decode(SnapshotCodec.encode([value])).first)
        XCTAssertEqual(decoded, value)
    }

    private func operation(
        id: UUID, device: UUID, clock: UInt64, base: UUID? = nil,
        action: OperationAction, activity: Activity
    ) -> BabyTrackerDomain.Operation {
        BabyTrackerDomain.Operation(
            id: id, entityID: activity.id, authorDeviceID: device,
            lamport: clock, parentRevisions: base.map { [$0] } ?? [],
            baseRevision: base, action: action, payload: .activity(activity)
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", value))!
    }
}
