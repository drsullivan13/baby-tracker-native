import Foundation

@main
struct VerifyLegacy {
    static func main() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let first = try LegacyImporter.decode(data, authorDeviceID: UUID())
        let second = try LegacyImporter.decode(data, authorDeviceID: UUID())
        guard first.operations == second.operations else { throw CheckFailure.deviceDependentImport }
        let merged = try OperationReducer.replay(OperationReducer.validatedUnion(first.operations, second.operations))
        guard merged.activities.count == first.activityCount else { throw CheckFailure.recordCount }
        let serialized = try SnapshotCodec.encode(first.operations)
        let roundtrip = try SnapshotCodec.decode(serialized)
        guard roundtrip == first.operations.sorted(by: OperationReducer.operationPrecedes) else { throw CheckFailure.roundtrip }
        let envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rows = envelope["activities"] as! [[String: Any]]
        for row in rows {
            let id = (row["id"] as! NSNumber).int64Value
            let kind = row["kind"] as! String
            let nativeID = StableUUID.make("legacy-v1|\(kind)|\(id)")
            guard let activity = merged.activities[nativeID], activity.kind.rawValue == kind else { throw CheckFailure.fieldMismatch }
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let text = row["startedAt"] as! String
            let original = fmt.date(from: text) ?? ISO8601DateFormatter().date(from: text)
            guard activity.startedAt == original,
                activity.amountMl == (row["amountMl"] as? NSNumber)?.doubleValue,
                activity.feedMethod?.rawValue == row["feedMethod"] as? String,
                activity.feedSide?.rawValue == row["feedSide"] as? String,
                activity.bottleMilkType?.rawValue == row["bottleMilkType"] as? String,
                activity.diaperKind?.rawValue == row["diaperKind"] as? String else { throw CheckFailure.fieldMismatch }
        }
        print("PASS: \(first.activityCount) source activities validated with exact timestamp/type/amount fidelity, device-independent identifiers, duplicate-safe merge, and lossless internal snapshot roundtrip. No records were imported into an app or printed.")
    }
}
enum CheckFailure: Error { case deviceDependentImport, recordCount, roundtrip, fieldMismatch }
