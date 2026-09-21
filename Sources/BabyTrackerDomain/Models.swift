import Foundation

public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case feed, diaper, sleep, custom
}

public enum FeedMethod: String, Codable, CaseIterable, Sendable {
    case bottle, breast
}

public enum FeedSide: String, Codable, CaseIterable, Sendable {
    case left, right, both
}

public enum BottleMilkType: String, Codable, CaseIterable, Sendable {
    case breastMilk = "breast_milk"
    case formula
}

public enum DiaperKind: String, Codable, CaseIterable, Sendable {
    case wet, dirty, both
}

public struct Activity: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: ActivityKind
    public var startedAt: Date
    public var endedAt: Date?
    public var isRunning: Bool
    public var feedMethod: FeedMethod?
    public var feedSide: FeedSide?
    public var amountMl: Double?
    public var bottleMilkType: BottleMilkType?
    public var diaperKind: DiaperKind?
    public var customTrackerID: UUID?
    public var customName: String?
    public var customColor: String?
    public var deleted: Bool

    public init(
        id: UUID = UUID(), kind: ActivityKind, startedAt: Date,
        endedAt: Date? = nil, isRunning: Bool = false,
        feedMethod: FeedMethod? = nil, feedSide: FeedSide? = nil,
        amountMl: Double? = nil, bottleMilkType: BottleMilkType? = nil,
        diaperKind: DiaperKind? = nil, customTrackerID: UUID? = nil,
        customName: String? = nil, customColor: String? = nil,
        deleted: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isRunning = isRunning
        self.feedMethod = feedMethod
        self.feedSide = feedSide
        self.amountMl = amountMl
        self.bottleMilkType = bottleMilkType
        self.diaperKind = diaperKind
        self.customTrackerID = customTrackerID
        self.customName = customName
        self.customColor = customColor
        self.deleted = deleted
    }
}

public struct CustomTracker: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var color: String
    public var archived: Bool

    public init(id: UUID = UUID(), name: String, color: String, archived: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.archived = archived
    }
}

public enum EntityPayload: Codable, Equatable, Sendable {
    case activity(Activity)
    case tracker(CustomTracker)

    private enum CodingKeys: String, CodingKey { case type, activity, tracker }
    private enum PayloadType: String, Codable { case activity, tracker }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        switch try box.decode(PayloadType.self, forKey: .type) {
        case .activity: self = .activity(try box.decode(Activity.self, forKey: .activity))
        case .tracker: self = .tracker(try box.decode(CustomTracker.self, forKey: .tracker))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .activity(let value):
            try box.encode(PayloadType.activity, forKey: .type)
            try box.encode(value, forKey: .activity)
        case .tracker(let value):
            try box.encode(PayloadType.tracker, forKey: .type)
            try box.encode(value, forKey: .tracker)
        }
    }

    public var entityID: UUID {
        switch self {
        case .activity(let value): return value.id
        case .tracker(let value): return value.id
        }
    }
}

public enum OperationAction: String, Codable, Sendable {
    case create, edit, stopTimer, delete, restore, archive, restoreTracker, resolveConflict
}

public struct Operation: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 1
    public var id: UUID
    public var entityID: UUID
    public var authorDeviceID: UUID
    public var lamport: UInt64
    public var schemaVersion: Int
    public var parentRevisions: [UUID]
    public var baseRevision: UUID?
    public var action: OperationAction
    public var payload: EntityPayload
    public var resolvesOperationIDs: [UUID]

    public init(
        id: UUID = UUID(), entityID: UUID, authorDeviceID: UUID,
        lamport: UInt64, schemaVersion: Int = currentSchemaVersion,
        parentRevisions: [UUID] = [], baseRevision: UUID? = nil,
        action: OperationAction, payload: EntityPayload,
        resolvesOperationIDs: [UUID] = []
    ) {
        self.id = id
        self.entityID = entityID
        self.authorDeviceID = authorDeviceID
        self.lamport = lamport
        self.schemaVersion = schemaVersion
        self.parentRevisions = parentRevisions
        self.baseRevision = baseRevision
        self.action = action
        self.payload = payload
        self.resolvesOperationIDs = resolvesOperationIDs
    }
}

public struct OperationSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var operations: [Operation]

    public init(schemaVersion: Int = Operation.currentSchemaVersion, operations: [Operation]) {
        self.schemaVersion = schemaVersion
        self.operations = operations
    }
}

public struct RetainedConflict: Identifiable, Equatable, Sendable {
    public var id: String { operationIDs.map(\.uuidString).joined(separator: ":") }
    public let entityID: UUID
    public let operationIDs: [UUID]
    public let versions: [EntityPayload]
}

public enum DomainError: LocalizedError, Equatable {
    case incompatibleSchema(Int)
    case malformed(String)
    case operationIDCollision(UUID)
    case entityMismatch
    case invalidActivity(String)
    case invalidTracker(String)
    case lamportOverflow

    public var errorDescription: String? {
        switch self {
        case .incompatibleSchema(let version): return "Unsupported data schema version \(version)."
        case .malformed(let message): return "Malformed data: \(message)"
        case .operationIDCollision(let id): return "Operation ID \(id) was reused with different content."
        case .entityMismatch: return "An operation payload does not match its entity ID."
        case .invalidActivity(let message): return "Invalid activity: \(message)"
        case .invalidTracker(let message): return "Invalid custom tracker: \(message)"
        case .lamportOverflow: return "The local revision clock is exhausted."
        }
    }
}

public enum Validation {
    public static func validate(_ operation: Operation) throws {
        guard operation.schemaVersion == Operation.currentSchemaVersion else {
            throw DomainError.incompatibleSchema(operation.schemaVersion)
        }
        guard operation.entityID == operation.payload.entityID else { throw DomainError.entityMismatch }
        switch operation.payload {
        case .activity(let activity): try validate(activity)
        case .tracker(let tracker): try validate(tracker)
        }
    }

    public static func validate(_ activity: Activity) throws {
        guard activity.startedAt.timeIntervalSince1970.isFinite else {
            throw DomainError.invalidActivity("start time is not finite")
        }
        if let end = activity.endedAt {
            guard end.timeIntervalSince1970.isFinite, end >= activity.startedAt else {
                throw DomainError.invalidActivity("end time precedes start time")
            }
        }
        if activity.isRunning && activity.endedAt != nil {
            throw DomainError.invalidActivity("a running timer cannot have an end time")
        }
        if let amount = activity.amountMl, (!amount.isFinite || amount <= 0 || amount > 10_000) {
            throw DomainError.invalidActivity("amount must be between 0 and 10,000 ml")
        }
        if activity.isRunning,
           activity.kind != .sleep && !(activity.kind == .feed && activity.feedMethod == .breast) {
            throw DomainError.invalidActivity("only sleep and breastfeed records can run timers")
        }
        if activity.kind == .feed, activity.feedMethod == nil {
            throw DomainError.invalidActivity("feed method is required")
        }
        if activity.feedMethod == .breast, activity.feedSide == nil {
            throw DomainError.invalidActivity("breastfeeds require a side")
        }
        if activity.feedMethod == .bottle, activity.feedSide != nil {
            throw DomainError.invalidActivity("a bottle feed cannot have a breast side")
        }
        if activity.feedMethod == .breast,
           activity.amountMl != nil || activity.bottleMilkType != nil {
            throw DomainError.invalidActivity("bottle details cannot be used for a breastfeed")
        }
        if activity.kind != .feed,
           activity.feedMethod != nil || activity.feedSide != nil ||
           activity.amountMl != nil || activity.bottleMilkType != nil {
            throw DomainError.invalidActivity("feed details require feed kind")
        }
        if activity.kind != .diaper, activity.diaperKind != nil {
            throw DomainError.invalidActivity("diaper details require diaper kind")
        }
        if activity.kind == .diaper, activity.diaperKind == nil {
            throw DomainError.invalidActivity("diaper kind is required")
        }
        if activity.kind == .custom {
            guard activity.customTrackerID != nil,
                  !(activity.customName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                  !(activity.customColor?.isEmpty ?? true) else {
                throw DomainError.invalidActivity("custom records require tracker snapshots")
            }
            guard activity.customColor?.range(
                of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression
            ) != nil else {
                throw DomainError.invalidActivity("custom record color must be a six-digit hex value")
            }
        } else if activity.customTrackerID != nil || activity.customName != nil || activity.customColor != nil {
            throw DomainError.invalidActivity("custom tracker details require custom kind")
        }
    }

    public static func validate(_ tracker: CustomTracker) throws {
        let name = tracker.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else {
            throw DomainError.invalidTracker("name must contain 1–80 characters")
        }
        guard tracker.color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else {
            throw DomainError.invalidTracker("color must be a six-digit hex value")
        }
    }
}
