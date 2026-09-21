import Foundation
import SwiftUI
import BabyTrackerDomain
import BabyTrackerPersistence

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var dataset = ReducedDataset()
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published private(set) var undoActivity: Activity?
    @Published var selectedDay = Date()

    private(set) var store: OperationStore?
    private(set) var importService: ImportService?
    var afterLocalSave: (() -> Void)?

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains(SimulatorAuditFixture.launchArgument) {
            do {
                let fixture = try SimulatorAuditFixture.make(
                    arguments: ProcessInfo.processInfo.arguments
                )
                store = fixture.store
                importService = fixture.importService
                selectedDay = fixture.selectedDay
                try reload()
            } catch {
                errorMessage = "The synthetic visual-audit fixture could not be prepared. \(error.localizedDescription)"
            }
            return
        }
        #endif
        do {
            let store = try OperationStore()
            self.store = store
            self.importService = ImportService(store: store)
            _ = try self.importService?.stagedURLs()
            try reload()
        } catch {
            errorMessage = "Baby Tracker could not open its private local database. Your data was not reset. \(error.localizedDescription)"
        }
    }

    var activities: [Activity] {
        dataset.activities.values.sorted { $0.startedAt > $1.startedAt }
    }

    var activeActivities: [Activity] { activities.filter { !$0.deleted } }
    var deletedActivities: [Activity] { activities.filter(\.deleted) }
    var runningActivities: [Activity] { activeActivities.filter(\.isRunning) }
    var trackers: [CustomTracker] {
        dataset.trackers.values.sorted {
            if $0.archived != $1.archived { return !$0.archived }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var lastFeed: Activity? { activeActivities.first { $0.kind == .feed } }

    func reload() throws {
        guard let store else { throw AppModelError.storeUnavailable }
        dataset = try store.reducedDataset()
    }

    @discardableResult
    func save(_ activity: Activity, action: OperationAction? = nil) -> Bool {
        performLocalSave {
            guard let store else { throw AppModelError.storeUnavailable }
            let resolvedAction = action ?? (dataset.activities[activity.id] == nil ? .create : .edit)
            _ = try store.append(action: resolvedAction, payload: .activity(activity))
        }
    }

    @discardableResult
    func save(_ tracker: CustomTracker, action: OperationAction? = nil) -> Bool {
        performLocalSave {
            guard let store else { throw AppModelError.storeUnavailable }
            let resolvedAction = action ?? (dataset.trackers[tracker.id] == nil ? .create : .edit)
            _ = try store.append(action: resolvedAction, payload: .tracker(tracker))
        }
    }

    func stop(_ activity: Activity, at date: Date = Date()) {
        var stopped = activity
        stopped.endedAt = max(date, activity.startedAt)
        stopped.isRunning = false
        save(stopped, action: .stopTimer)
    }

    @discardableResult
    func setDeleted(_ activity: Activity, deleted: Bool) -> Bool {
        var changed = activity
        changed.deleted = deleted
        changed.isRunning = deleted ? false : changed.isRunning
        guard save(changed, action: deleted ? .delete : .restore) else { return false }
        undoActivity = deleted ? activity : nil
        notice = deleted ? "Record moved to Recently Deleted." : "Record restored."
        return true
    }

    func undoDelete() {
        guard let activity = undoActivity else { return }
        _ = setDeleted(activity, deleted: false)
    }

    func resolve(_ conflict: RetainedConflict, choosing payload: EntityPayload) {
        guard payload.entityID == conflict.entityID, conflict.versions.contains(payload) else {
            errorMessage = "This conflict version is unavailable. Reopen the conflict and choose again."
            return
        }
        performLocalSave {
            guard let store else { throw AppModelError.storeUnavailable }
            _ = try store.append(
                action: .resolveConflict, payload: payload,
                resolves: conflict.operationIDs
            )
        }
    }

    func receiveSnapshot(_ data: Data) throws {
        guard backupAcknowledged else { throw AppModelError.privacySetupRequired }
        guard let store else { throw AppModelError.storeUnavailable }
        _ = try store.mergeSnapshot(data)
        try reload()
    }

    func snapshotData() throws -> Data {
        guard backupAcknowledged else { throw AppModelError.privacySetupRequired }
        guard let store else { throw AppModelError.storeUnavailable }
        return try store.snapshotData()
    }

    var backupAcknowledged: Bool {
        get { importService?.hasAcknowledgedBackupDisabled ?? false }
        set {
            importService?.hasAcknowledgedBackupDisabled = newValue
            objectWillChange.send()
        }
    }

    func importStagedFile() {
        do {
            guard let importService else { throw AppModelError.storeUnavailable }
            let summary = try importService.importStagedFile()
            try reload()
            notice = "Read \(summary.activitiesRead) activities and \(summary.trackersRead) trackers. Added \(summary.addedOperations) new operations."
            if summary.addedOperations > 0 { afterLocalSave?() }
        } catch ImportError.savedButCleanupFailed(let summary) {
            do { try reload() } catch { errorMessage = error.localizedDescription; return }
            notice = "History saved (\(summary.activitiesRead) records). The temporary import file still needs removal."
            errorMessage = "The import succeeded, but its staged file could not be removed. No repeat import is needed."
            if summary.addedOperations > 0 { afterLocalSave?() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func performLocalSave(_ work: () throws -> Void) -> Bool {
        do {
            guard backupAcknowledged else { throw AppModelError.privacySetupRequired }
            try work()
            try reload()
            afterLocalSave?()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

enum AppModelError: LocalizedError {
    case storeUnavailable, privacySetupRequired
    var errorDescription: String? {
        switch self {
        case .storeUnavailable: return "The local data store is unavailable. Nothing was saved."
        case .privacySetupRequired: return "Check cloud-backup settings for this app, then confirm the privacy check in Settings before logging, importing, or syncing history."
        }
    }
}
