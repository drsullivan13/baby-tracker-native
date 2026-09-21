import Foundation
import BabyTrackerDomain

public struct StagedImportSummary: Equatable, Sendable {
    public var addedOperations: Int
    public var activitiesRead: Int
    public var trackersRead: Int
}

public final class ImportService {
    public static let acknowledgmentKey = "babyTracker.importBackupDisabledAcknowledged.v1"
    public static let maximumImportBytes = 16 * 1024 * 1024

    private let store: OperationStore
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let stagingRoot: URL?

    public init(
        store: OperationStore, fileManager: FileManager = .default,
        defaults: UserDefaults = .standard, stagingRoot: URL? = nil
    ) {
        self.store = store
        self.fileManager = fileManager
        self.defaults = defaults
        self.stagingRoot = stagingRoot
    }

    public var hasAcknowledgedBackupDisabled: Bool {
        get { defaults.bool(forKey: acknowledgmentKey) }
        set { defaults.set(newValue, forKey: acknowledgmentKey) }
    }

    /// Creates the only supported import destination before a transfer starts.
    @discardableResult
    public func prepareStagingDirectory() throws -> URL {
        let directory = try stagingDirectory()
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        #else
        let attributes: [FileAttributeKey: Any] = [:]
        #endif
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: attributes
        )
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path
        )
        #endif
        try excludeFromBackup(directory)
        return directory
    }

    public func stagedURLs() throws -> [URL] {
        [try prepareStagingDirectory().appendingPathComponent("records.json")]
    }

    public func importStagedFile() throws -> StagedImportSummary {
        guard hasAcknowledgedBackupDisabled else {
            throw ImportError.backupAcknowledgmentRequired
        }
        guard let url = try stagedURLs().first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw ImportError.noStagedFile
        }
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path
        )
        #endif
        try excludeFromBackup(url)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw ImportError.invalidStagedFile }
        guard let size = values.fileSize, size <= Self.maximumImportBytes else {
            throw ImportError.fileTooLarge
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maximumImportBytes + 1) ?? Data()
        guard data.count <= Self.maximumImportBytes else { throw ImportError.fileTooLarge }
        let result = try LegacyImporter.decode(data, authorDeviceID: store.deviceID)
        let count = try store.merge(result.operations)
        let summary = StagedImportSummary(
            addedOperations: count,
            activitiesRead: result.activityCount,
            trackersRead: result.trackerCount
        )
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw ImportError.savedButCleanupFailed(summary)
        }
        return summary
    }

    private var acknowledgmentKey: String {
        let device = (try? store.deviceID.uuidString) ?? "unavailable"
        return "\(Self.acknowledgmentKey).\(device)"
    }

    private func stagingDirectory() throws -> URL {
        if let stagingRoot {
            return stagingRoot.appendingPathComponent("Imports", isDirectory: true)
        }
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return supportRoot.appendingPathComponent("Imports", isDirectory: true)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try mutable.setResourceValues(values)
    }
}

public enum ImportError: LocalizedError, Equatable {
    case backupAcknowledgmentRequired
    case noStagedFile
    case invalidStagedFile
    case fileTooLarge
    case savedButCleanupFailed(StagedImportSummary)

    public var errorDescription: String? {
        switch self {
        case .backupAcknowledgmentRequired:
            return "Confirm that device backup is disabled before importing."
        case .noStagedFile:
            return "No records.json file was found in an Imports folder."
        case .invalidStagedFile:
            return "The staged import is not a regular file."
        case .fileTooLarge:
            return "The staged import exceeds the 16 MiB limit."
        case .savedButCleanupFailed:
            return "The import was saved, but the staged file could not be removed."
        }
    }
}
