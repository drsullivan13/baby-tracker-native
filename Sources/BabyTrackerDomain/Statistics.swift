import Foundation

public struct DayStatistics: Equatable, Sendable {
    public var day: Date
    public var feeds: Int
    public var amountMl: Double
    public var diaperTotal: Int
    public var wetDiapers: Int
    public var dirtyDiapers: Int
    public var sleepSeconds: TimeInterval

    public var amountFlOz: Double { amountMl / 29.5735295625 }
}

public struct PeriodAverages: Equatable, Sendable {
    public var days: Int
    public var startDate: Date
    public var endDate: Date
    public var feeds: Double
    public var bottleFeeds: Double
    public var nursingFeeds: Double
    public var amountMl: Double
    public var diapers: Double
    public var wetDiapers: Double
    public var dirtyDiapers: Double
    public var sleepSeconds: TimeInterval
}

public enum BabyStatistics {
    public static let defaultTimeZone = TimeZone(identifier: "America/New_York")!

    public static func dayStatistics(
        activities: [Activity], containing date: Date,
        asOf: Date,
        timeZone: TimeZone = defaultTimeZone
    ) -> DayStatistics {
        let interval = dayInterval(containing: date, timeZone: timeZone)
        var output = DayStatistics(
            day: interval.start, feeds: 0, amountMl: 0, diaperTotal: 0,
            wetDiapers: 0, dirtyDiapers: 0, sleepSeconds: 0
        )
        for activity in activities where !activity.deleted {
            if activity.startedAt >= interval.start && activity.startedAt < interval.end {
                switch activity.kind {
                case .feed:
                    output.feeds += 1
                    output.amountMl += activity.amountMl ?? 0
                case .diaper:
                    output.diaperTotal += 1
                    if activity.diaperKind == .wet || activity.diaperKind == .both { output.wetDiapers += 1 }
                    if activity.diaperKind == .dirty || activity.diaperKind == .both { output.dirtyDiapers += 1 }
                default: break
                }
            }
            if activity.kind == .sleep {
                let end = activity.endedAt ?? (activity.isRunning ? asOf : activity.startedAt)
                let overlapStart = max(activity.startedAt, interval.start)
                let overlapEnd = min(end, interval.end)
                if overlapEnd > overlapStart {
                    output.sleepSeconds += overlapEnd.timeIntervalSince(overlapStart)
                }
            }
        }
        return output
    }

    public static func averages(
        activities: [Activity], endingOn date: Date, days: Int,
        asOf: Date,
        timeZone: TimeZone = defaultTimeZone
    ) -> PeriodAverages {
        precondition(days > 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let endDay = calendar.startOfDay(for: date)
        let values = (0..<days).reversed().map { offset -> DayStatistics in
            let day = calendar.date(byAdding: .day, value: -offset, to: endDay)!
            return dayStatistics(activities: activities, containing: day, asOf: asOf, timeZone: timeZone)
        }
        return periodAverages(
            activities: activities,
            dailyStatistics: values,
            timeZone: timeZone
        )
    }

    /// Returns only whole calendar days. If the selected day is today or later,
    /// the period ends yesterday so an in-progress day never depresses an average.
    public static func completedDailyStatistics(
        activities: [Activity], selectedDay: Date, days: Int,
        asOf: Date,
        timeZone: TimeZone = defaultTimeZone
    ) -> [DayStatistics] {
        precondition(days > 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let selectedStart = calendar.startOfDay(for: selectedDay)
        let todayStart = calendar.startOfDay(for: asOf)
        let endDay = selectedStart >= todayStart
            ? calendar.date(byAdding: .day, value: -1, to: todayStart)!
            : selectedStart
        return (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: endDay)!
            return dayStatistics(
                activities: activities,
                containing: day,
                asOf: asOf,
                timeZone: timeZone
            )
        }
    }

    public static func completedAverages(
        activities: [Activity], selectedDay: Date, days: Int,
        asOf: Date,
        timeZone: TimeZone = defaultTimeZone
    ) -> PeriodAverages {
        let values = completedDailyStatistics(
            activities: activities,
            selectedDay: selectedDay,
            days: days,
            asOf: asOf,
            timeZone: timeZone
        )
        return periodAverages(
            activities: activities,
            dailyStatistics: values,
            timeZone: timeZone
        )
    }

    private static func periodAverages(
        activities: [Activity],
        dailyStatistics values: [DayStatistics],
        timeZone: TimeZone
    ) -> PeriodAverages {
        precondition(!values.isEmpty)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startDate = values.first!.day
        let endDate = values.last!.day
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDate)!
        let feeds = activities.filter {
            !$0.deleted && $0.kind == .feed &&
            $0.startedAt >= startDate && $0.startedAt < endExclusive
        }
        let divisor = Double(values.count)
        return PeriodAverages(
            days: values.count,
            startDate: startDate,
            endDate: endDate,
            feeds: Double(values.reduce(0) { $0 + $1.feeds }) / divisor,
            bottleFeeds: Double(feeds.filter { $0.feedMethod == .bottle }.count) / divisor,
            nursingFeeds: Double(feeds.filter { $0.feedMethod == .breast }.count) / divisor,
            amountMl: values.reduce(0) { $0 + $1.amountMl } / divisor,
            diapers: Double(values.reduce(0) { $0 + $1.diaperTotal }) / divisor,
            wetDiapers: Double(values.reduce(0) { $0 + $1.wetDiapers }) / divisor,
            dirtyDiapers: Double(values.reduce(0) { $0 + $1.dirtyDiapers }) / divisor,
            sleepSeconds: values.reduce(0) { $0 + $1.sleepSeconds } / divisor
        )
    }

    public static func estimatedNextFeed(activities: [Activity]) -> Date? {
        let dates = activities
            .filter { !$0.deleted && $0.kind == .feed }
            .map(\.startedAt)
            .sorted()
        guard dates.count >= 4 else { return nil }
        let recent = Array(dates.suffix(8))
        let gaps = zip(recent.dropFirst(), recent).map { $0.timeIntervalSince($1) }
        let usable = Array(gaps.suffix(8))
        guard !usable.isEmpty else { return nil }
        return dates.last!.addingTimeInterval(usable.reduce(0, +) / Double(usable.count))
    }

    private static func dayInterval(containing date: Date, timeZone: TimeZone) -> DateInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.dateInterval(of: .day, for: date)!
    }
}
