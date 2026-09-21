import XCTest
import BabyTrackerDomain

final class StatisticsTests: XCTestCase {
    func testDSTDayAndMidnightSleepSplit() throws {
        let zone = TimeZone(identifier: "America/New_York")!
        let sleep = Activity(
            kind: .sleep,
            startedAt: iso("2026-03-08T04:30:00Z"),
            endedAt: iso("2026-03-08T08:30:00Z")
        )
        let saturday = BabyStatistics.dayStatistics(
            activities: [sleep], containing: iso("2026-03-08T04:45:00Z"),
            asOf: sleep.endedAt!, timeZone: zone
        )
        let sunday = BabyStatistics.dayStatistics(
            activities: [sleep], containing: iso("2026-03-08T12:00:00Z"),
            asOf: sleep.endedAt!, timeZone: zone
        )
        XCTAssertEqual(saturday.sleepSeconds, 30 * 60, accuracy: 0.1)
        XCTAssertEqual(sunday.sleepSeconds, 3.5 * 60 * 60, accuracy: 0.1)
    }

    func testZeroDaysAndDiaperBothCountCorrectly() {
        let date = iso("2026-09-21T12:00:00Z")
        let diaper = Activity(kind: .diaper, startedAt: date, diaperKind: .both)
        let stats = BabyStatistics.dayStatistics(activities: [diaper], containing: date, asOf: date)
        XCTAssertEqual(stats.diaperTotal, 1)
        XCTAssertEqual(stats.wetDiapers, 1)
        XCTAssertEqual(stats.dirtyDiapers, 1)
        let average = BabyStatistics.averages(
            activities: [diaper], endingOn: date, days: 7, asOf: date
        )
        XCTAssertEqual(average.diapers, 1.0 / 7.0, accuracy: 0.0001)
    }

    func testNextFeedRequiresFourAndUsesRecentGaps() {
        let base = Date(timeIntervalSince1970: 1_000)
        let three = (0..<3).map { Activity(kind: .feed, startedAt: base.addingTimeInterval(Double($0) * 100)) }
        XCTAssertNil(BabyStatistics.estimatedNextFeed(activities: three))
        let nine = (0..<9).map { Activity(kind: .feed, startedAt: base.addingTimeInterval(Double($0) * 120)) }
        XCTAssertEqual(
            BabyStatistics.estimatedNextFeed(activities: nine),
            base.addingTimeInterval(9 * 120)
        )
    }

    func testCompletedAveragesExcludePartialToday() {
        let asOf = iso("2026-09-21T16:00:00Z")
        let yesterday = iso("2026-09-20T16:00:00Z")
        let today = Activity(
            kind: .feed, startedAt: asOf,
            feedMethod: .bottle, amountMl: 120, bottleMilkType: .formula
        )
        let priorBottle = Activity(
            kind: .feed, startedAt: yesterday,
            feedMethod: .bottle, amountMl: 60, bottleMilkType: .breastMilk
        )
        let priorNursing = Activity(
            kind: .feed, startedAt: yesterday.addingTimeInterval(3_600),
            feedMethod: .breast, feedSide: .left
        )

        let average = BabyStatistics.completedAverages(
            activities: [today, priorBottle, priorNursing],
            selectedDay: asOf,
            days: 7,
            asOf: asOf
        )

        XCTAssertEqual(average.endDate, dayStart(yesterday))
        XCTAssertEqual(average.feeds, 2.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(average.bottleFeeds, 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(average.nursingFeeds, 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(average.amountMl, 60.0 / 7.0, accuracy: 0.0001)
    }

    func testCompletedAveragesIncludeSelectedPastDayAndCountDiaperKinds() {
        let asOf = iso("2026-09-21T16:00:00Z")
        let selected = iso("2026-09-19T16:00:00Z")
        let both = Activity(kind: .diaper, startedAt: selected, diaperKind: .both)
        let dirty = Activity(
            kind: .diaper,
            startedAt: selected.addingTimeInterval(600),
            diaperKind: .dirty
        )

        let average = BabyStatistics.completedAverages(
            activities: [both, dirty],
            selectedDay: selected,
            days: 7,
            asOf: asOf
        )

        XCTAssertEqual(average.endDate, dayStart(selected))
        XCTAssertEqual(average.diapers, 2.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(average.wetDiapers, 1.0 / 7.0, accuracy: 0.0001)
        XCTAssertEqual(average.dirtyDiapers, 2.0 / 7.0, accuracy: 0.0001)
    }

    func testCompletedDailyStatisticsAreOldestToNewestAcrossDST() {
        let asOf = iso("2026-03-10T16:00:00Z")
        let values = BabyStatistics.completedDailyStatistics(
            activities: [],
            selectedDay: asOf,
            days: 3,
            asOf: asOf
        )

        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.last?.day, dayStart(iso("2026-03-09T16:00:00Z")))
        XCTAssertLessThan(values[0].day, values[1].day)
        XCTAssertLessThan(values[1].day, values[2].day)
    }

    private func iso(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func dayStart(_ value: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BabyStatistics.defaultTimeZone
        return calendar.startOfDay(for: value)
    }
}
