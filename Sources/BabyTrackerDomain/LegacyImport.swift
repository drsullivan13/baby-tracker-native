import Foundation

public struct ImportResult: Equatable, Sendable {
    public var operations: [Operation]
    public var activityCount: Int
    public var trackerCount: Int
}

public enum LegacyImporter {
    public static func decode(_ data: Data, authorDeviceID _: UUID) throws -> ImportResult {
        let legacyAuthorID = StableUUID.make("legacy-v1|author")
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw DomainError.malformed(error.localizedDescription) }

        let activities: [[String: Any]]
        let trackers: [[String: Any]]
        if let array = object as? [[String: Any]] {
            activities = array
            trackers = []
        } else if let dictionary = object as? [String: Any] {
            if let version = dictionary["version"] ?? dictionary["schemaVersion"] {
                guard try integer(version, field: "version") == 1 else {
                    throw DomainError.incompatibleSchema(
                        Int(try integer(version, field: "version"))
                    )
                }
            }
            guard let activityArray = dictionary["activities"] as? [[String: Any]] else {
                throw DomainError.malformed("activities must be an array")
            }
            activities = activityArray
            if let value = dictionary["trackers"] {
                guard let trackerArray = value as? [[String: Any]] else {
                    throw DomainError.malformed("trackers must be an array")
                }
                trackers = trackerArray
            } else {
                trackers = []
            }
        } else {
            throw DomainError.malformed("expected an array or object")
        }

        var operations: [Operation] = []
        var trackerIDs = Set<Int64>()
        var importedTrackers: [Int64: CustomTracker] = [:]
        for record in trackers {
            let idNumber = try integer(record["id"], field: "tracker.id")
            guard trackerIDs.insert(idNumber).inserted else {
                throw DomainError.malformed("duplicate tracker.id \(idNumber)")
            }
            let id = StableUUID.make("legacy-v1|tracker|\(idNumber)")
            let tracker = CustomTracker(
                id: id,
                name: try string(record["name"], field: "tracker.name"),
                color: try optionalString(record["color"], field: "tracker.color") ?? "#53AD99",
                archived: try optionalBool(record["archived"], field: "tracker.archived") ?? false
            )
            try Validation.validate(tracker)
            importedTrackers[idNumber] = tracker
            operations.append(Operation(
                id: StableUUID.make("legacy-v1|operation|tracker|\(idNumber)"),
                entityID: id, authorDeviceID: legacyAuthorID,
                lamport: 1,
                action: tracker.archived ? .archive : .create,
                payload: .tracker(tracker)
            ))
        }

        var activityIDs = Set<Int64>()
        var synthesizedTrackers: [Int64: CustomTracker] = [:]
        for record in activities {
            let idNumber = try integer(record["id"], field: "activity.id")
            guard activityIDs.insert(idNumber).inserted else {
                throw DomainError.malformed("duplicate activity.id \(idNumber)")
            }
            let kind = try enumValue(ActivityKind.self, record["kind"] ?? record["type"], field: "activity.kind")
            let id = StableUUID.make("legacy-v1|\(kind.rawValue)|\(idNumber)")
            let startedAt = try date(record["startedAt"] ?? record["started_at"], field: "activity.startedAt")
            let trackerNumber = try optionalInteger(
                record["customTrackerId"] ?? record["custom_tracker_id"],
                field: "activity.customTrackerId"
            )
            let trackerID = trackerNumber.map { StableUUID.make("legacy-v1|tracker|\($0)") }
            let customName = try optionalString(
                record["customTrackerName"] ?? record["custom_name"],
                field: "activity.customTrackerName"
            )
            let customColor = try optionalString(
                record["customTrackerColor"] ?? record["custom_color"],
                field: "activity.customTrackerColor"
            )
            let activity = Activity(
                id: id, kind: kind, startedAt: startedAt,
                endedAt: try optionalDate(record["endedAt"] ?? record["ended_at"]),
                isRunning: try optionalBool(record["isRunning"], field: "activity.isRunning") ?? false,
                feedMethod: try optionalEnum(FeedMethod.self, record["feedMethod"] ?? record["feed_method"], field: "activity.feedMethod"),
                feedSide: try optionalEnum(FeedSide.self, record["feedSide"] ?? record["feed_side"], field: "activity.feedSide"),
                amountMl: try optionalDouble(record["amountMl"] ?? record["amount_ml"], field: "activity.amountMl"),
                bottleMilkType: try optionalEnum(BottleMilkType.self, record["bottleMilkType"] ?? record["bottle_milk_type"], field: "activity.bottleMilkType"),
                diaperKind: try optionalEnum(DiaperKind.self, record["diaperKind"] ?? record["diaper_kind"], field: "activity.diaperKind"),
                customTrackerID: trackerID,
                customName: customName,
                customColor: customColor,
                deleted: try optionalBool(record["deleted"], field: "activity.deleted") ?? false
            )
            try Validation.validate(activity)
            if kind == .custom, let trackerNumber {
                if importedTrackers[trackerNumber] == nil {
                    let snapshot = CustomTracker(
                        id: trackerID!,
                        name: customName!,
                        color: customColor!
                    )
                    try Validation.validate(snapshot)
                    if let existing = synthesizedTrackers[trackerNumber], existing != snapshot {
                        throw DomainError.malformed(
                            "custom tracker \(trackerNumber) has inconsistent snapshots"
                        )
                    }
                    synthesizedTrackers[trackerNumber] = snapshot
                }
            }
            operations.append(Operation(
                id: StableUUID.make("legacy-v1|operation|\(kind.rawValue)|\(idNumber)"),
                entityID: id, authorDeviceID: legacyAuthorID,
                lamport: 1,
                action: activity.deleted ? .delete : .create,
                payload: .activity(activity)
            ))
        }
        for (idNumber, tracker) in synthesizedTrackers.sorted(by: { $0.key < $1.key }) {
            operations.append(Operation(
                id: StableUUID.make("legacy-v1|operation|tracker|\(idNumber)"),
                entityID: tracker.id, authorDeviceID: legacyAuthorID,
                lamport: 1, action: .create, payload: .tracker(tracker)
            ))
        }
        operations = try OperationReducer.validatedUnion([], operations)
        return ImportResult(
            operations: operations,
            activityCount: activities.count,
            trackerCount: trackers.count + synthesizedTrackers.count
        )
    }

    private static func integer(_ value: Any?, field: String) throws -> Int64 {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: number.objCType)) else {
            throw DomainError.malformed("\(field) must be a nonnegative integer")
        }
        let double = number.doubleValue
        guard double.isFinite, double >= 0, double.rounded(.towardZero) == double,
              double <= Double(Int64.max),
              NSNumber(value: number.int64Value).decimalValue == number.decimalValue else {
            throw DomainError.malformed("\(field) must be a nonnegative integer")
        }
        return number.int64Value
    }
    private static func optionalInteger(_ value: Any?, field: String) throws -> Int64? {
        guard value != nil, !(value is NSNull) else { return nil }
        return try integer(value, field: field)
    }
    private static func string(_ value: Any?, field: String) throws -> String {
        guard let value = value as? String else { throw DomainError.malformed("\(field) must be a string") }
        return value
    }
    private static func date(_ value: Any?, field: String) throws -> Date {
        guard let value else { throw DomainError.malformed("\(field) is required") }
        if let seconds = value as? NSNumber, CFGetTypeID(seconds) != CFBooleanGetTypeID(),
           seconds.doubleValue.isFinite {
            return Date(timeIntervalSince1970: seconds.doubleValue)
        }
        if let text = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = formatter.date(from: text) { return parsed }
            formatter.formatOptions = [.withInternetDateTime]
            if let parsed = formatter.date(from: text) { return parsed }
        }
        throw DomainError.malformed("\(field) must be an ISO-8601 string or epoch")
    }
    private static func optionalDate(_ value: Any?) throws -> Date? {
        guard value != nil, !(value is NSNull) else { return nil }
        return try date(value, field: "activity.endedAt")
    }
    private static func optionalDouble(_ value: Any?, field: String) throws -> Double? {
        guard value != nil, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else {
            throw DomainError.malformed("\(field) must be numeric")
        }
        return number.doubleValue
    }
    private static func optionalString(_ value: Any?, field: String) throws -> String? {
        guard value != nil, !(value is NSNull) else { return nil }
        guard let value = value as? String else {
            throw DomainError.malformed("\(field) must be a string")
        }
        return value
    }
    private static func optionalBool(_ value: Any?, field: String) throws -> Bool? {
        guard value != nil, !(value is NSNull) else { return nil }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw DomainError.malformed("\(field) must be a boolean")
        }
        return number.boolValue
    }
    private static func enumValue<T: RawRepresentable>(
        _ type: T.Type, _ value: Any?, field: String
    ) throws -> T where T.RawValue == String {
        guard let raw = value as? String, let result = T(rawValue: raw) else {
            throw DomainError.malformed("\(field) has an unknown value")
        }
        return result
    }
    private static func optionalEnum<T: RawRepresentable>(
        _ type: T.Type, _ value: Any?, field: String
    ) throws -> T? where T.RawValue == String {
        guard value != nil, !(value is NSNull) else { return nil }
        guard let raw = value as? String, let result = T(rawValue: raw) else {
            throw DomainError.malformed("\(field) has an unknown value")
        }
        return result
    }
}

public enum StableUUID {
    public static func make(_ text: String) -> UUID {
        let hashes = hash(text)
        var bytes = withUnsafeBytes(of: hashes.0.bigEndian, Array.init)
        bytes += withUnsafeBytes(of: hashes.1.bigEndian, Array.init)
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func hash(_ text: String) -> (UInt64, UInt64) {
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x84222325cbf29ce4
        for byte in text.utf8 {
            first = (first ^ UInt64(byte)) &* 0x100000001b3
            second = (second ^ UInt64(byte &+ 31)) &* 0x100000001b3
        }
        return (first, second)
    }
}
