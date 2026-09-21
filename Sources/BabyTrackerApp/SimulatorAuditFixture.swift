#if DEBUG && targetEnvironment(simulator)
import Foundation
import BabyTrackerDomain
import BabyTrackerPersistence

/// Synthetic, disposable data used only by explicitly opted-in simulator UI audits.
enum SimulatorAuditFixture {
    static let launchArgument = "--visual-audit-fixture"
    private static let emptyArgument = "--visual-audit-empty"
    private static let identifierArgument = "--visual-audit-fixture-id"

    struct Result {
        let store: OperationStore
        let importService: ImportService
        let selectedDay: Date
    }

    static func make(arguments: [String]) throws -> Result {
        let identifier = fixtureIdentifier(in: arguments)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BabyTrackerVisualAudit", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true
        )

        let store = try OperationStore(
            storeURL: root.appendingPathComponent("BabyTracker.sqlite")
        )
        let suiteName = "com.dansullivan.babytracker.visual-audit.\(identifier)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw FixtureError.defaultsUnavailable
        }
        defaults.removePersistentDomain(forName: suiteName)
        let importService = ImportService(
            store: store, defaults: defaults, stagingRoot: root
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BabyStatistics.defaultTimeZone
        let selectedDay = calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 20)
        )!

        if arguments.contains(emptyArgument) {
            importService.hasAcknowledgedBackupDisabled = false
        } else {
            try seed(store: store, selectedDay: selectedDay, calendar: calendar)
            importService.hasAcknowledgedBackupDisabled = true
        }
        return Result(
            store: store, importService: importService, selectedDay: selectedDay
        )
    }

    private static func seed(
        store: OperationStore, selectedDay: Date, calendar: Calendar
    ) throws {
        let tracker = CustomTracker(
            id: uuid(1), name: "Tummy time", color: "#56C5B2"
        )
        try store.append(action: .create, payload: .tracker(tracker))

        for dayOffset in 0..<14 {
            let day = calendar.date(
                byAdding: .day, value: -dayOffset, to: selectedDay
            )!
            let bottleStart = calendar.date(
                byAdding: .minute, value: 6 * 60 + dayOffset * 3, to: day
            )!
            let nursingStart = calendar.date(
                byAdding: .minute, value: 9 * 60 + dayOffset * 2, to: day
            )!
            let sleepStart = calendar.date(
                byAdding: .minute, value: 60 + dayOffset, to: day
            )!
            let customStart = calendar.date(
                byAdding: .minute, value: 12 * 60 + dayOffset, to: day
            )!

            try store.append(action: .create, payload: .activity(Activity(
                id: uuid(100 + dayOffset), kind: .feed, startedAt: bottleStart,
                feedMethod: .bottle, amountMl: Double(70 + (dayOffset % 5) * 10),
                bottleMilkType: dayOffset.isMultiple(of: 2) ? .breastMilk : .formula
            )))
            try store.append(action: .create, payload: .activity(Activity(
                id: uuid(200 + dayOffset), kind: .feed, startedAt: nursingStart,
                endedAt: nursingStart.addingTimeInterval(Double(12 + dayOffset % 9) * 60),
                feedMethod: .breast,
                feedSide: FeedSide.allCases[dayOffset % FeedSide.allCases.count]
            )))
            try store.append(action: .create, payload: .activity(Activity(
                id: uuid(300 + dayOffset), kind: .diaper,
                startedAt: calendar.date(byAdding: .minute, value: 10 * 60, to: day)!,
                diaperKind: DiaperKind.allCases[dayOffset % DiaperKind.allCases.count]
            )))
            try store.append(action: .create, payload: .activity(Activity(
                id: uuid(400 + dayOffset), kind: .sleep, startedAt: sleepStart,
                endedAt: sleepStart.addingTimeInterval(Double(95 + dayOffset * 7) * 60)
            )))
            try store.append(action: .create, payload: .activity(Activity(
                id: uuid(500 + dayOffset), kind: .custom, startedAt: customStart,
                customTrackerID: tracker.id, customName: tracker.name,
                customColor: tracker.color
            )))
        }

        let deletedStart = calendar.date(
            byAdding: .minute, value: 15 * 60, to: selectedDay
        )!
        var deleted = Activity(
            id: uuid(700), kind: .diaper, startedAt: deletedStart,
            diaperKind: .both
        )
        try store.append(action: .create, payload: .activity(deleted))
        deleted.deleted = true
        try store.append(action: .delete, payload: .activity(deleted))

        let conflictStart = calendar.date(
            byAdding: .minute, value: 13 * 60, to: selectedDay
        )!
        let original = Activity(
            id: uuid(800), kind: .feed, startedAt: conflictStart,
            feedMethod: .bottle, amountMl: 100, bottleMilkType: .formula
        )
        let base = try store.append(
            action: .create, payload: .activity(original)
        )

        var localEdit = original
        localEdit.amountMl = 110
        var peerEdit = original
        peerEdit.amountMl = 125
        let edits = [
            BabyTrackerDomain.Operation(
                id: uuid(801), entityID: original.id, authorDeviceID: uuid(901),
                lamport: base.lamport + 1, parentRevisions: [base.id],
                baseRevision: base.id, action: .edit, payload: .activity(localEdit)
            ),
            BabyTrackerDomain.Operation(
                id: uuid(802), entityID: original.id, authorDeviceID: uuid(902),
                lamport: base.lamport + 1, parentRevisions: [base.id],
                baseRevision: base.id, action: .edit, payload: .activity(peerEdit)
            )
        ]
        try store.merge(edits)
    }

    private static func fixtureIdentifier(in arguments: [String]) -> String {
        guard let index = arguments.firstIndex(of: identifierArgument),
              arguments.indices.contains(index + 1) else {
            return "default"
        }
        let candidate = arguments[index + 1]
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return candidate.isEmpty ? "default" : String(candidate.prefix(80))
    }

    private static func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }

    private enum FixtureError: LocalizedError {
        case defaultsUnavailable

        var errorDescription: String? {
            "A temporary preferences suite could not be created."
        }
    }
}
#endif
