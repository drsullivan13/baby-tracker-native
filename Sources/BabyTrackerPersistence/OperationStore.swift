import CoreData
import Foundation
import BabyTrackerDomain

public final class OperationStore {
    private enum Field {
        static let operationID = "operationID"
        static let entityID = "entityID"
        static let payload = "payload"
        static let stateID = "stateID"
        static let deviceID = "deviceID"
        static let lamport = "lamport"
    }

    public let container: NSPersistentContainer
    public let storeURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(storeURL: URL? = nil, inMemory: Bool = false) throws {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "BabyTracker-v1", managedObjectModel: model)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()

        if inMemory {
            self.storeURL = URL(fileURLWithPath: "/dev/null")
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            let url = try storeURL ?? Self.defaultStoreURL()
            self.storeURL = url
            try Self.secureDirectory(url.deletingLastPathComponent())
            let description = NSPersistentStoreDescription(url: url)
            #if os(iOS)
            description.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)
            #endif
            // This package currently ships only v1. Do not infer a migration from an
            // unknown model, because Core Data may treat unrelated entities as deletions.
            description.setOption(false as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(false as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
            container.persistentStoreDescriptions = [description]
        }

        var loadingError: Error?
        container.loadPersistentStores { _, error in loadingError = error }
        if let loadingError { throw loadingError }
        container.viewContext.mergePolicy = NSErrorMergePolicy
        container.viewContext.undoManager = nil
        if !inMemory {
            try Self.secureStoreFiles(at: self.storeURL)
        }
        try ensureState()
    }

    public var deviceID: UUID {
        get throws { try readState().deviceID }
    }

    public var lamport: UInt64 {
        get throws { try readState().lamport }
    }

    public func operations() throws -> [BabyTrackerDomain.Operation] {
        let context = container.viewContext
        var result: Result<[BabyTrackerDomain.Operation], Error>!
        context.performAndWait {
            result = Result {
                let request = NSFetchRequest<NSManagedObject>(entityName: "StoredOperation")
                let objects = try context.fetch(request)
                return try objects.map { object in
                    guard let data = object.value(forKey: Field.payload) as? Data else {
                        throw DomainError.malformed("stored operation payload is missing")
                    }
                    let operation = try decoder.decode(BabyTrackerDomain.Operation.self, from: data)
                    try Validation.validate(operation)
                    return operation
                }.sorted(by: OperationReducer.operationPrecedes)
            }
        }
        return try result.get()
    }

    public func reducedDataset() throws -> ReducedDataset {
        try OperationReducer.replay(operations())
    }

    public func snapshotData() throws -> Data {
        try SnapshotCodec.encode(operations())
    }

    /// Validates the complete union before changing the store. A rejected batch leaves no writes.
    @discardableResult
    public func merge(_ incoming: [BabyTrackerDomain.Operation]) throws -> Int {
        let existing = try operations()
        let union = try OperationReducer.validatedUnion(existing, incoming)
        _ = try OperationReducer.replay(union)
        let existingIDs = Set(existing.map(\.id))
        let additions = union.filter { !existingIDs.contains($0.id) }
        guard !additions.isEmpty else { return 0 }

        let context = container.newBackgroundContext()
        context.mergePolicy = NSErrorMergePolicy
        var transactionResult: Result<Void, Error>!
        context.performAndWait {
            transactionResult = Result {
                for operation in additions {
                    let object = NSEntityDescription.insertNewObject(forEntityName: "StoredOperation", into: context)
                    object.setValue(operation.id.uuidString, forKey: Field.operationID)
                    object.setValue(operation.entityID.uuidString, forKey: Field.entityID)
                    object.setValue(try encoder.encode(operation), forKey: Field.payload)
                }
                let state = try Self.fetchState(in: context)
                let received = additions.map(\.lamport).max() ?? 0
                let current = UInt64(max(0, state.value(forKey: Field.lamport) as? Int64 ?? 0))
                let maximum = max(current, received)
                guard maximum < UInt64(Int64.max) else { throw DomainError.lamportOverflow }
                state.setValue(Int64(maximum), forKey: Field.lamport)
                try context.save()
            }
        }
        try transactionResult.get()
        container.viewContext.reset()
        if storeURL.path != "/dev/null" { try Self.secureStoreFiles(at: storeURL) }
        return additions.count
    }

    @discardableResult
    public func append(
        action: OperationAction, payload: EntityPayload,
        resolves: [UUID] = []
    ) throws -> BabyTrackerDomain.Operation {
        let dataset = try reducedDataset()
        // A stop changes timing only; a view may hold a value from before a remote edit.
        var payload = payload
        if action == .stopTimer, case .activity(let requested) = payload {
            guard var current = dataset.activities[requested.id], current.isRunning,
                  let end = requested.endedAt else {
                throw DomainError.invalidActivity("this timer is no longer running")
            }
            current.endedAt = max(end, current.startedAt)
            current.isRunning = false
            payload = .activity(current)
        }
        let state = try readState()
        var factory = OperationFactory(authorDeviceID: state.deviceID, lamport: state.lamport)
        let revision = dataset.revisions[payload.entityID]
        let operation = try factory.make(
            action: action, payload: payload, baseRevision: revision,
            parents: Array(Set((revision.map { [$0] } ?? []) + resolves)), resolves: resolves
        )
        _ = try merge([operation])
        return operation
    }

    public func mergeSnapshot(_ data: Data) throws -> Int {
        try merge(SnapshotCodec.decode(data))
    }

    private struct State {
        var deviceID: UUID
        var lamport: UInt64
    }

    private func ensureState() throws {
        let context = container.viewContext
        var result: Result<Void, Error>!
        context.performAndWait {
            result = Result {
                let request = NSFetchRequest<NSManagedObject>(entityName: "StoreState")
                request.fetchLimit = 1
                guard try context.fetch(request).isEmpty else { return }
                let object = NSEntityDescription.insertNewObject(forEntityName: "StoreState", into: context)
                object.setValue("local", forKey: Field.stateID)
                object.setValue(UUID().uuidString, forKey: Field.deviceID)
                object.setValue(Int64(0), forKey: Field.lamport)
                try context.save()
            }
        }
        try result.get()
    }

    private func readState() throws -> State {
        let context = container.viewContext
        var result: Result<State, Error>!
        context.performAndWait {
            result = Result {
                let object = try Self.fetchState(in: context)
                guard let text = object.value(forKey: Field.deviceID) as? String,
                      let id = UUID(uuidString: text) else {
                    throw DomainError.malformed("local device identity is missing")
                }
                let value = object.value(forKey: Field.lamport) as? Int64 ?? 0
                guard value >= 0 else { throw DomainError.malformed("local revision clock is invalid") }
                return State(deviceID: id, lamport: UInt64(value))
            }
        }
        return try result.get()
    }

    private static func fetchState(in context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "StoreState")
        request.fetchLimit = 1
        guard let state = try context.fetch(request).first else {
            throw DomainError.malformed("local store state is missing")
        }
        return state
    }

    private static func defaultStoreURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("BabyTracker", isDirectory: true)
            .appendingPathComponent("BabyTracker.sqlite")
    }

    private static func secureDirectory(_ url: URL) throws {
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: attributes
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path
        )
        #endif
    }

    private static func secureStoreFiles(at url: URL) throws {
        for candidate in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            #if os(iOS)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete], ofItemAtPath: candidate.path
            )
            #endif
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = candidate
            try mutable.setResourceValues(values)
        }
    }

    public static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["BabyTracker-v1"]

        let operation = NSEntityDescription()
        operation.name = "StoredOperation"
        operation.managedObjectClassName = "NSManagedObject"
        operation.properties = [
            attribute(Field.operationID, .stringAttributeType, optional: false),
            attribute(Field.entityID, .stringAttributeType, optional: false),
            attribute(Field.payload, .binaryDataAttributeType, optional: false)
        ]
        operation.uniquenessConstraints = [[Field.operationID]]

        let state = NSEntityDescription()
        state.name = "StoreState"
        state.managedObjectClassName = "NSManagedObject"
        state.properties = [
            attribute(Field.stateID, .stringAttributeType, optional: false),
            attribute(Field.deviceID, .stringAttributeType, optional: false),
            attribute(Field.lamport, .integer64AttributeType, optional: false)
        ]
        state.uniquenessConstraints = [[Field.stateID]]
        model.entities = [operation, state]
        return model
    }

    private static func attribute(
        _ name: String, _ type: NSAttributeType, optional: Bool
    ) -> NSAttributeDescription {
        let value = NSAttributeDescription()
        value.name = name
        value.attributeType = type
        value.isOptional = optional
        return value
    }
}
