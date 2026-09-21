import Foundation

public struct ReducedDataset: Equatable, Sendable {
    public var activities: [UUID: Activity] = [:]
    public var trackers: [UUID: CustomTracker] = [:]
    public var revisions: [UUID: UUID] = [:]
    public var conflicts: [RetainedConflict] = []

    public init() {}
}

public enum OperationReducer {
    public static func validatedUnion(_ lhs: [Operation], _ rhs: [Operation]) throws -> [Operation] {
        var byID: [UUID: Operation] = [:]
        for operation in lhs + rhs {
            try Validation.validate(operation)
            if let existing = byID[operation.id], existing != operation {
                throw DomainError.operationIDCollision(operation.id)
            }
            byID[operation.id] = operation
        }
        return byID.values.sorted(by: operationPrecedes)
    }

    public static func replay(_ operations: [Operation]) throws -> ReducedDataset {
        let ordered = try validatedUnion([], operations)
        var result = ReducedDataset()
        let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: ordered, by: \.entityID)

        for (entityID, entityOperations) in grouped {
            var heads: [UUID: Operation] = [:]
            for operation in entityOperations {
                let acknowledged = Set(operation.resolvesOperationIDs)
                heads = heads.filter { id, _ in
                    !acknowledged.contains(id) && !isAncestor(id, of: operation, in: byID)
                }
                heads[operation.id] = operation
            }

            let unresolved = heads.values.sorted(by: operationPrecedes)
            guard var selected = unresolved.first else { continue }
            for candidate in unresolved.dropFirst() {
                selected = concurrentWinner(between: selected, and: candidate, in: byID)
            }

            switch effectivePayload(of: selected, in: byID) {
            case .activity(let value): result.activities[value.id] = value
            case .tracker(let value): result.trackers[value.id] = value
            }
            result.revisions[entityID] = selected.id

            guard unresolved.count > 1 else { continue }
            result.conflicts.append(RetainedConflict(
                entityID: entityID,
                operationIDs: unresolved.map(\.id).sorted(by: uuidPrecedes),
                versions: unresolved.map { effectivePayload(of: $0, in: byID) }
            ))
        }
        result.conflicts.sort { $0.id < $1.id }
        return result
    }

    private static func effectivePayload(of selected: Operation, in operations: [UUID: Operation]) -> EntityPayload {
        switch selected.payload {
            case .activity(var activity):
                let ancestry = causalClosure(of: selected, in: operations)
                let statusOperations = ancestry.filter {
                    $0.action == .delete || $0.action == .restore ||
                    $0.action == .resolveConflict
                }
                if let status = statusOperations.max(by: operationPrecedes) {
                    if status.action == .delete {
                        activity.deleted = true
                    } else if status.action == .restore {
                        activity.deleted = false
                    } else if status.action == .resolveConflict {
                        activity.deleted = status.payload.activityValue?.deleted ?? activity.deleted
                    }
                }
                if let stop = ancestry.filter({ $0.action == .stopTimer }).max(by: operationPrecedes) {
                    if activity.endedAt == nil, let end = stop.payload.activityValue?.endedAt {
                        activity.endedAt = max(end, activity.startedAt)
                    }
                    activity.isRunning = false
                }
                if activity.deleted {
                    activity.isRunning = false
                }
                return .activity(activity)
            case .tracker(var tracker):
                let ancestry = causalClosure(of: selected, in: operations)
                let archiveOperations = ancestry.filter {
                    $0.action == .archive || $0.action == .restoreTracker ||
                    $0.action == .resolveConflict
                }
                if let status = archiveOperations.max(by: operationPrecedes) {
                    if status.action == .archive {
                        tracker.archived = true
                    } else if status.action == .restoreTracker {
                        tracker.archived = false
                    } else if status.action == .resolveConflict {
                        tracker.archived = status.payload.trackerValue?.archived ?? tracker.archived
                    }
                }
                return .tracker(tracker)
            }
    }

    public static func operationPrecedes(_ lhs: Operation, _ rhs: Operation) -> Bool {
        if lhs.lamport != rhs.lamport { return lhs.lamport < rhs.lamport }
        if lhs.authorDeviceID != rhs.authorDeviceID {
            return lhs.authorDeviceID.uuidString < rhs.authorDeviceID.uuidString
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func concurrentWinner(between lhs: Operation, and rhs: Operation, in operations: [UUID: Operation]) -> Operation {
        // Terminal status survives metadata edits on that branch. Comparing only the
        // head action would let a concurrent edit resurrect an edited tombstone.
        let left = terminalState(lhs, in: operations), right = terminalState(rhs, in: operations)
        if left.deleted != right.deleted { return left.deleted ? lhs : rhs }
        if left.stopped != right.stopped { return left.stopped ? lhs : rhs }
        return operationPrecedes(lhs, rhs) ? rhs : lhs
    }

    private static func terminalState(_ operation: Operation, in operations: [UUID: Operation]) -> (deleted: Bool, stopped: Bool) {
        guard case .activity(let value) = operation.payload else { return (false, false) }
        let ancestry = causalClosure(of: operation, in: operations)
        let status = ancestry.filter { [.delete, .restore, .resolveConflict].contains($0.action) }.max(by: operationPrecedes)
        let deleted: Bool
        switch status?.action {
        case .delete: deleted = true
        case .restore: deleted = false
        case .resolveConflict: deleted = status?.payload.activityValue?.deleted ?? value.deleted
        default: deleted = value.deleted
        }
        return (deleted, ancestry.contains { $0.action == .stopTimer })
    }

    private static func isAncestor(
        _ ancestorID: UUID, of operation: Operation, in operations: [UUID: Operation]
    ) -> Bool {
        causalClosure(of: operation, in: operations).contains { $0.id == ancestorID }
    }

    private static func causalClosure(
        of operation: Operation, in operations: [UUID: Operation]
    ) -> [Operation] {
        var result: [Operation] = [operation]
        var pending = operation.parentRevisions
        if let base = operation.baseRevision { pending.append(base) }
        var visited = Set([operation.id])
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let parent = operations[id] else { continue }
            result.append(parent)
            pending.append(contentsOf: parent.parentRevisions)
            if let base = parent.baseRevision { pending.append(base) }
        }
        return result
    }

    private static func uuidPrecedes(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

private extension EntityPayload {
    var activityValue: Activity? {
        guard case .activity(let value) = self else { return nil }
        return value
    }

    var trackerValue: CustomTracker? {
        guard case .tracker(let value) = self else { return nil }
        return value
    }
}

public struct OperationFactory {
    public let authorDeviceID: UUID
    public private(set) var lamport: UInt64

    public init(authorDeviceID: UUID, lamport: UInt64 = 0) {
        self.authorDeviceID = authorDeviceID
        self.lamport = lamport
    }

    public mutating func observe(_ operations: [Operation]) throws {
        let received = operations.map(\.lamport).max() ?? 0
        let maximum = max(received, lamport)
        guard maximum < UInt64.max else { throw DomainError.lamportOverflow }
        lamport = maximum + 1
    }

    public mutating func make(
        action: OperationAction, payload: EntityPayload,
        baseRevision: UUID?, parents: [UUID] = [],
        resolves: [UUID] = []
    ) throws -> Operation {
        guard lamport < UInt64.max else { throw DomainError.lamportOverflow }
        lamport += 1
        let operation = Operation(
            entityID: payload.entityID, authorDeviceID: authorDeviceID,
            lamport: lamport, parentRevisions: parents,
            baseRevision: baseRevision, action: action, payload: payload,
            resolvesOperationIDs: resolves
        )
        try Validation.validate(operation)
        return operation
    }
}

public enum SnapshotCodec {
    public static func encode(_ operations: [Operation]) throws -> Data {
        let snapshot = OperationSnapshot(operations: try OperationReducer.validatedUnion([], operations))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> [Operation] {
        let decoder = JSONDecoder()
        let snapshot: OperationSnapshot
        do {
            snapshot = try decoder.decode(OperationSnapshot.self, from: data)
        } catch {
            throw DomainError.malformed(error.localizedDescription)
        }
        guard snapshot.schemaVersion == Operation.currentSchemaVersion else {
            throw DomainError.incompatibleSchema(snapshot.schemaVersion)
        }
        return try OperationReducer.validatedUnion([], snapshot.operations)
    }
}
