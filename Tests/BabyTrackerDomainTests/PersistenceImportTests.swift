import XCTest
import CoreData
import BabyTrackerDomain
import BabyTrackerPersistence

final class PersistenceImportTests: XCTestCase {
    func testCoreDataReopenPreservesIdentityClockAndOperations() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/BabyTrackerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        let first = try OperationStore(storeURL: url)
        let originalDeviceID = try first.deviceID
        let activity = Activity(kind: .feed, startedAt: Date(), feedMethod: .breast, feedSide: .left)
        let originalOperation = try first.append(action: .create, payload: .activity(activity))
        let clock = try first.lamport

        let reopened = try OperationStore(storeURL: url)
        XCTAssertEqual(try reopened.deviceID, originalDeviceID)
        XCTAssertGreaterThanOrEqual(try reopened.lamport, clock)
        let persisted = try XCTUnwrap(reopened.reducedDataset().activities[activity.id])
        XCTAssertEqual(persisted.id, activity.id)
        XCTAssertEqual(persisted.startedAt, activity.startedAt)
        XCTAssertEqual(persisted.feedSide, activity.feedSide)
        XCTAssertEqual(try reopened.operations().first?.payload, .activity(activity))
        XCTAssertEqual(try reopened.merge([originalOperation]), 0)
    }

    func testFailedBatchIsAtomicAndRepeatImportAddsZero() throws {
        let store = try OperationStore(inMemory: true)
        let device = try store.deviceID
        let goodActivity = Activity(kind: .diaper, startedAt: Date(), diaperKind: .wet)
        let good = BabyTrackerDomain.Operation(
            id: UUID(), entityID: goodActivity.id, authorDeviceID: device,
            lamport: 1, action: .create, payload: .activity(goodActivity)
        )
        let badActivity = Activity(kind: .sleep, startedAt: Date(), endedAt: Date.distantPast)
        let bad = BabyTrackerDomain.Operation(
            id: UUID(), entityID: badActivity.id, authorDeviceID: device,
            lamport: 2, action: .create, payload: .activity(badActivity)
        )
        XCTAssertThrowsError(try store.merge([good, bad]))
        XCTAssertEqual(try store.operations().count, 0)

        let json = """
        {"activities":[{"id":1,"kind":"feed","startedAt":"2026-01-01T12:00:00Z",
        "feedMethod":"bottle","bottleMilkType":"formula","amountMl":90}],"trackers":[]}
        """.data(using: .utf8)!
        let imported = try LegacyImporter.decode(json, authorDeviceID: device)
        XCTAssertEqual(try store.merge(imported.operations), 1)
        XCTAssertEqual(try store.merge(imported.operations), 0)
        XCTAssertEqual(try store.operations().count, 1)
    }

    func testMalformedLegacyImportDoesNotWrite() throws {
        let store = try OperationStore(inMemory: true)
        let malformed = #"[{"id":1,"kind":"unknown","startedAt":"2026-01-01T00:00:00Z"}]"#.data(using: .utf8)!
        XCTAssertThrowsError(try LegacyImporter.decode(malformed, authorDeviceID: store.deviceID))
        XCTAssertTrue(try store.operations().isEmpty)
    }

    func testLegacyImportUsesExactFieldsFractionalDatesAndStableOperations() throws {
        let json = """
        {"version":1,"activities":[{
          "id":7,"kind":"custom","startedAt":"2026-01-01T12:00:00.123Z",
          "customTrackerId":4,"customTrackerName":"Medicine",
          "customTrackerColor":"#123ABC"
        }],"trackers":[{"id":4,"name":"Medicine","color":"#123ABC","archived":true}]}
        """.data(using: .utf8)!
        let first = try LegacyImporter.decode(json, authorDeviceID: UUID())
        let second = try LegacyImporter.decode(json, authorDeviceID: UUID())

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.activityCount, 1)
        XCTAssertEqual(first.trackerCount, 1)
        XCTAssertTrue(first.operations.allSatisfy { $0.lamport == 1 })
        XCTAssertEqual(Set(first.operations.map(\.authorDeviceID)).count, 1)
        var importedActivity: Activity?
        for operation in first.operations {
            if case .activity(let value) = operation.payload {
                importedActivity = value
                break
            }
        }
        let activity = try XCTUnwrap(importedActivity)
        XCTAssertEqual(
            activity.startedAt.timeIntervalSince1970,
            1_767_268_800.123,
            accuracy: 0.000_001
        )
        let reduced = try OperationReducer.replay(first.operations)
        XCTAssertEqual(reduced.activities[activity.id], activity)
        XCTAssertTrue(try XCTUnwrap(reduced.trackers[activity.customTrackerID!]).archived)
    }

    func testLegacyImportRejectsCoercedNumbersDuplicatesEnumsAndVersions() throws {
        let invalidDocuments = [
            #"[{"id":true,"kind":"sleep","startedAt":0}]"#,
            #"[{"id":1.0,"kind":"sleep","startedAt":0}]"#,
            #"[{"id":-1,"kind":"sleep","startedAt":0}]"#,
            #"[{"id":1,"kind":"sleep","startedAt":0,"amountMl":"90"}]"#,
            #"[{"id":1,"kind":"sleep","startedAt":0,"isRunning":"yes"}]"#,
            #"[{"id":1,"kind":"feed","startedAt":0,"feedMethod":"tube"}]"#,
            #"{"version":2,"activities":[],"trackers":[]}"#,
            #"{"activities":[{"id":1,"kind":"sleep","startedAt":0},{"id":1,"kind":"sleep","startedAt":1}],"trackers":[]}"#
        ]
        for document in invalidDocuments {
            XCTAssertThrowsError(
                try LegacyImporter.decode(
                    try XCTUnwrap(document.data(using: .utf8)),
                    authorDeviceID: UUID()
                ),
                "accepted \(document)"
            )
        }
    }

    func testLegacyImportValidatesKindSpecificFields() throws {
        let invalidDocuments = [
            #"[{"id":1,"kind":"feed","startedAt":0}]"#,
            #"[{"id":1,"kind":"diaper","startedAt":0}]"#,
            #"[{"id":1,"kind":"sleep","startedAt":0,"amountMl":90}]"#,
            #"[{"id":1,"kind":"feed","startedAt":0,"feedMethod":"breast","feedSide":"left","amountMl":90}]"#,
            #"[{"id":1,"kind":"diaper","startedAt":0,"isRunning":true,"diaperKind":"wet"}]"#
        ]
        for document in invalidDocuments {
            XCTAssertThrowsError(
                try LegacyImporter.decode(
                    try XCTUnwrap(document.data(using: .utf8)),
                    authorDeviceID: UUID()
                ),
                "accepted \(document)"
            )
        }
    }

    func testImportStagingUsesApplicationSupportRootAndRejectsOversizeBeforeRead() throws {
        let root = URL(fileURLWithPath: "/private/tmp/BabyTrackerImport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "BabyTrackerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try OperationStore(inMemory: true)
        let service = ImportService(store: store, defaults: defaults, stagingRoot: root)
        service.hasAcknowledgedBackupDisabled = true
        let urls = try service.stagedURLs()
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].deletingLastPathComponent(), root.appendingPathComponent("Imports"))

        let oversized = Data(count: ImportService.maximumImportBytes + 1)
        try oversized.write(to: urls[0])
        XCTAssertThrowsError(try service.importStagedFile()) { error in
            XCTAssertEqual(error as? ImportError, .fileTooLarge)
        }
        XCTAssertTrue(try store.operations().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
    }

    func testAcknowledgmentIsScopedPerStoreDevice() throws {
        let suite = "BabyTrackerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ImportService(store: try OperationStore(inMemory: true), defaults: defaults)
        let second = ImportService(store: try OperationStore(inMemory: true), defaults: defaults)
        first.hasAcknowledgedBackupDisabled = true
        XCTAssertTrue(first.hasAcknowledgedBackupDisabled)
        XCTAssertFalse(second.hasAcknowledgedBackupDisabled)
    }

    func testSuccessfulStagedImportCleansUpOnlyAfterCommit() throws {
        let root = URL(fileURLWithPath: "/private/tmp/BabyTrackerImport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "BabyTrackerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = try OperationStore(inMemory: true)
        let service = ImportService(store: store, defaults: defaults, stagingRoot: root)
        service.hasAcknowledgedBackupDisabled = true
        let url = try XCTUnwrap(service.stagedURLs().first)
        let data = #"[{"id":1,"kind":"diaper","startedAt":0,"diaperKind":"wet"}]"#
            .data(using: .utf8)!
        try data.write(to: url)

        let summary = try service.importStagedFile()

        XCTAssertEqual(summary.addedOperations, 1)
        XCTAssertEqual(try store.operations().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testUnknownOnDiskSchemaFailsWithoutResettingStore() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/BabyTrackerSchema-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("unknown.sqlite")

        let unknownModel = NSManagedObjectModel()
        unknownModel.versionIdentifiers = ["BabyTracker-v99"]
        let entity = NSEntityDescription()
        entity.name = "UnknownEntity"
        entity.managedObjectClassName = "NSManagedObject"
        let marker = NSAttributeDescription()
        marker.name = "marker"
        marker.attributeType = .stringAttributeType
        marker.isOptional = false
        entity.properties = [marker]
        unknownModel.entities = [entity]

        let creator = NSPersistentContainer(name: "Unknown", managedObjectModel: unknownModel)
        creator.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var creationError: Error?
        creator.loadPersistentStores { _, error in creationError = error }
        XCTAssertNil(creationError)
        let object = NSEntityDescription.insertNewObject(
            forEntityName: "UnknownEntity", into: creator.viewContext
        )
        object.setValue("preserve-me", forKey: "marker")
        try creator.viewContext.save()
        try creator.persistentStoreCoordinator.remove(
            try XCTUnwrap(creator.persistentStoreCoordinator.persistentStores.first)
        )

        XCTAssertThrowsError(try OperationStore(storeURL: url))

        let verifier = NSPersistentContainer(name: "Unknown", managedObjectModel: unknownModel)
        verifier.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var verificationError: Error?
        verifier.loadPersistentStores { _, error in verificationError = error }
        XCTAssertNil(verificationError)
        let request = NSFetchRequest<NSManagedObject>(entityName: "UnknownEntity")
        XCTAssertEqual(try verifier.viewContext.fetch(request).first?.value(forKey: "marker") as? String, "preserve-me")
    }

}
