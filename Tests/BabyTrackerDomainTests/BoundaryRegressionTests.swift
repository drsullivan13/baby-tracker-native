import XCTest
import BabyTrackerDomain
import BabyTrackerPersistence

final class BoundaryRegressionTests: XCTestCase {
    func testEventAtMidnightBelongsOnlyToFollowingDay() {
        let fmt = ISO8601DateFormatter()
        let day = fmt.date(from: "2026-01-01T17:00:00Z")!
        let midnight = fmt.date(from: "2026-01-02T05:00:00Z")!
        let activity = Activity(kind: .diaper, startedAt: midnight, diaperKind: .wet)
        XCTAssertEqual(BabyStatistics.dayStatistics(activities: [activity], containing: day, asOf: midnight).diaperTotal, 0)
        XCTAssertEqual(BabyStatistics.dayStatistics(activities: [activity], containing: midnight, asOf: midnight).diaperTotal, 1)
    }
    func testStoppedTimerCannotLoseEndThroughLaterEdit() throws {
        let store = try OperationStore(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var timer = Activity(kind: .sleep, startedAt: start, isRunning: true)
        _ = try store.append(action: .create, payload: .activity(timer))
        var ended = timer; ended.isRunning = false; ended.endedAt = start.addingTimeInterval(600)
        _ = try store.append(action: .stopTimer, payload: .activity(ended))
        timer.startedAt = start.addingTimeInterval(-60)
        _ = try store.append(action: .edit, payload: .activity(timer))
        let final = try XCTUnwrap(store.reducedDataset().activities[timer.id])
        XCTAssertFalse(final.isRunning)
        XCTAssertEqual(final.endedAt, ended.endedAt)
    }
    func testStopUsingStalePayloadPreservesLatestEdit() throws {
        let store = try OperationStore(inMemory: true)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Activity(kind: .feed, startedAt: start, isRunning: true, feedMethod: .breast, feedSide: .left)
        _ = try store.append(action: .create, payload: .activity(original))
        var edited = original; edited.feedSide = .right
        _ = try store.append(action: .edit, payload: .activity(edited))
        var stopped = original; stopped.isRunning = false; stopped.endedAt = start.addingTimeInterval(600)
        _ = try store.append(action: .stopTimer, payload: .activity(stopped))
        XCTAssertEqual(try store.reducedDataset().activities[original.id]?.feedSide, .right)
    }
}
