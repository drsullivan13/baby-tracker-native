import SwiftUI
import BabyTrackerDomain

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var sheet: QuickSheet?
    @State private var editing: Activity?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var summaryColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible()),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BabyTheme.quietText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                quickActions
                if model.runningActivities.count > 1 {
                    Label(
                        "\(model.runningActivities.count) timers are running. Stop each one when it finishes.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(BabyTheme.diaper)
                    .babyCard()
                }
                ForEach(model.runningActivities) { activity in
                    RunningTimerCard(activity: activity) { model.stop(activity) }
                }
                todaySummary
                lastFeed
                recent
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .babyScreenBackground()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editing) { ActivityEditor(model: model, activity: $0) }
        .sheet(item: $sheet) { selection in
            switch selection {
            case .feed: FeedEntryView(model: model)
            case .diaper: DiaperEntryView(model: model)
            case .sleep: SleepEntryView(model: model)
            case .custom(let tracker): CustomEntryView(model: model, tracker: tracker)
            }
        }
    }

    private var todaySummary: some View {
        let today = BabyStatistics.dayStatistics(
            activities: model.activeActivities,
            containing: Date(),
            asOf: Date()
        )
        return VStack(alignment: .leading, spacing: 16) {
            BabySectionHeader(title: "So far today", subtitle: "Your logged totals, through now")
            LazyVGrid(
                columns: summaryColumns,
                alignment: .leading,
                spacing: 14
            ) {
                TodayMetric(symbol: "drop.fill", value: "\(Int(today.amountMl.rounded())) ml", label: "Bottle volume", color: BabyTheme.feed)
                TodayMetric(symbol: "fork.knife", value: "\(today.feeds)", label: today.feeds == 1 ? "Feed" : "Feeds", color: BabyTheme.feed)
                TodayMetric(symbol: "drop", value: "\(today.wetDiapers)", label: "Wet diapers", color: BabyTheme.diaper)
                TodayMetric(symbol: "circle.hexagongrid", value: "\(today.dirtyDiapers)", label: "Dirty diapers", color: BabyTheme.diaper)
                TodayMetric(symbol: "moon.stars.fill", value: durationText(today.sleepSeconds), label: "Sleep", color: BabyTheme.sleep)
                TodayMetric(symbol: "circle.hexagongrid", value: "\(today.diaperTotal)", label: "Total diapers", color: BabyTheme.diaper)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .babyCard()
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            BabySectionHeader(title: "Quick log", subtitle: "One tap to get started")
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    QuickActionButton(title: "Feed", symbol: "drop.fill", color: BabyTheme.feed, identifier: "logFeed") { sheet = .feed }
                    QuickActionButton(title: "Diaper", symbol: "circle.hexagongrid.fill", color: BabyTheme.diaper, identifier: "logDiaper") { sheet = .diaper }
                    QuickActionButton(title: "Sleep", symbol: "moon.stars.fill", color: BabyTheme.sleep, identifier: "logSleep") { sheet = .sleep }
                }
            } else {
                HStack(spacing: 10) {
                    QuickActionButton(title: "Feed", symbol: "drop.fill", color: BabyTheme.feed, identifier: "logFeed") { sheet = .feed }
                    QuickActionButton(title: "Diaper", symbol: "circle.hexagongrid.fill", color: BabyTheme.diaper, identifier: "logDiaper") { sheet = .diaper }
                    QuickActionButton(title: "Sleep", symbol: "moon.stars.fill", color: BabyTheme.sleep, identifier: "logSleep") { sheet = .sleep }
                }
            }
            ForEach(model.trackers.filter { !$0.archived }) { tracker in
                QuickActionRow(title: tracker.name, subtitle: "\(customCount(tracker)) today · tap to log", symbol: "sparkles", color: Color(hex: tracker.color)) {
                    if model.save(Activity(kind: .custom, startedAt: Date(), customTrackerID: tracker.id,
                                           customName: tracker.name, customColor: tracker.color)) {
                        model.notice = "\(tracker.name) logged."
                    }
                } backdateAction: {
                    sheet = .custom(tracker)
                }
                .contextMenu { Button("Log at another time") { sheet = .custom(tracker) } }
            }
        }
        .babyCard()
    }

    private var lastFeed: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("LAST FEED", systemImage: "clock")
                .font(.caption.weight(.bold))
                .tracking(1.3)
                .foregroundStyle(BabyTheme.feed)
            if let feed = model.lastFeed {
                Text(feed.startedAt, style: .relative)
                    .font(.system(.title, design: .serif, weight: .semibold))
                Text(feed.title)
                    .foregroundStyle(BabyTheme.quietText)
                if let next = BabyStatistics.estimatedNextFeed(activities: model.activeActivities), next > Date() {
                    Text("Recent timing points to about \(next, format: .dateTime.hour().minute()).")
                        .font(.caption)
                        .foregroundStyle(BabyTheme.quietText)
                }
            } else {
                BabyEmptyState(
                    symbol: "drop",
                    title: "No feeds logged yet",
                    message: "Your first feed will appear here."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .babyCard()
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            BabySectionHeader(title: "Recent", subtitle: "Tap a record to review or edit")
            if model.activeActivities.isEmpty {
                BabyEmptyState(
                    symbol: "clock.arrow.circlepath",
                    title: "A quiet start",
                    message: "New logs will collect here in time order."
                )
            }
            ForEach(model.activeActivities.prefix(5)) { activity in
                Button { editing = activity } label: { ActivityRow(activity: activity) }.buttonStyle(.plain)
                if activity.id != model.activeActivities.prefix(5).last?.id { Divider() }
            }
        }
        .babyCard()
    }

    private func customCount(_ tracker: CustomTracker) -> Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = BabyStatistics.defaultTimeZone
        return model.activeActivities.filter { $0.customTrackerID == tracker.id && calendar.isDateInToday($0.startedAt) }.count
    }

}

private enum QuickSheet: Identifiable {
    case feed, diaper, sleep, custom(CustomTracker)
    var id: String {
        switch self {
        case .feed: return "feed"
        case .diaper: return "diaper"
        case .sleep: return "sleep"
        case .custom(let tracker): return tracker.id.uuidString
        }
    }
}

private struct QuickActionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var identifier: String? = nil
    let action: () -> Void
    let backdateAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.title3).foregroundStyle(color).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.body.weight(.semibold))
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier ?? title)
            Button(action: backdateAction) {
                VStack(spacing: 2) {
                    Image(systemName: "calendar.badge.clock")
                    Text("Choose time").font(.caption2.weight(.semibold))
                }
                .frame(minWidth: 72, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .tint(color)
            .accessibilityLabel("Log \(title) at another time")
        }
    }
}

private struct QuickActionButton: View {
    let title: String
    let symbol: String
    let color: Color
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(BabyTheme.raised, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

private struct TodayMetric: View {
    let symbol: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(BabyTheme.quietText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct ActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.symbol)
                .foregroundStyle(BabyTheme.color(for: activity.kind))
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(activity.title).font(.body.weight(.semibold))
                Text(activity.startedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if activity.isRunning {
                Text("RUNNING").font(.caption2.bold()).foregroundStyle(BabyTheme.sleep)
            } else if let end = activity.endedAt {
                Text(durationText(end.timeIntervalSince(activity.startedAt)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct RunningTimerCard: View {
    let activity: Activity
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: activity.kind == .sleep ? "moon.stars.fill" : "timer")
                .font(.title2)
                .foregroundStyle(BabyTheme.sleep)
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title).font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(durationText(context.date.timeIntervalSince(activity.startedAt), includeSeconds: true))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .accessibilityLabel("\(activity.title), elapsed time")
                    .accessibilityValue(durationText(context.date.timeIntervalSince(activity.startedAt), includeSeconds: true))
                }
            }
            Spacer()
            Button("Stop", action: stop)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(BabyTheme.feed)
        }
        .babyCard()
        .accessibilityElement(children: .contain)
    }
}

struct FeedEntryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var milk = BottleMilkType.breastMilk
    @State private var amount = ""
    @State private var startedAt = Date()
    @FocusState private var amountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BabySectionHeader(
                        title: "What happened?",
                        subtitle: "Use the time below if you’re catching up."
                    )
                }
                Section("Quick nursing log") {
                    (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                        Button("Left now") { nurse(.left, running: false) }
                            .buttonStyle(BabyPrimaryButtonStyle(color: BabyTheme.feed))
                            .accessibilityIdentifier("quickLeft")
                        Button("Right now") { nurse(.right, running: false) }
                            .buttonStyle(BabyPrimaryButtonStyle(color: BabyTheme.feed))
                            .accessibilityIdentifier("quickRight")
                    }
                }
                Section("Bottle") {
                    Picker("Contents", selection: $milk) {
                        Text("Breast milk").tag(BottleMilkType.breastMilk)
                        Text("Formula").tag(BottleMilkType.formula)
                    }.babyChoiceStyle()
                    TextField("Amount in ml (optional)", text: $amount)
                        .keyboardType(.decimalPad).focused($amountFocused)
                        .accessibilityIdentifier("bottleAmount")
                    Button("Log bottle") { bottle() }
                        .buttonStyle(BabyPrimaryButtonStyle(color: BabyTheme.feed))
                        .accessibilityIdentifier("logBottle")
                }
                Section("Time nursing") {
                    ForEach(FeedSide.allCases, id: \.self) { side in
                        Button {
                            nurse(side, running: true)
                        } label: {
                            Label("Start \(side.rawValue) timer", systemImage: "timer")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                }
                Section("When") { DatePicker("Started", selection: $startedAt) }
            }
            .babyFormStyle()
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { amountFocused = false } }
            }
            .modelErrorAlert(model)
        }
    }

    private func nurse(_ side: FeedSide, running: Bool) {
        if model.save(Activity(kind: .feed, startedAt: startedAt, isRunning: running,
                               feedMethod: .breast, feedSide: side)) { dismiss() }
    }
    private func bottle() {
        let text = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        let value = text.isEmpty ? nil : Double(text.replacingOccurrences(of: formatter.decimalSeparator ?? ".", with: "."))
        if !text.isEmpty && (value == nil || value! <= 0 || value! > 10_000) {
            model.errorMessage = "Enter a bottle amount greater than zero, or leave the field empty."; return
        }
        if model.save(Activity(kind: .feed, startedAt: startedAt, feedMethod: .bottle,
                               amountMl: value, bottleMilkType: milk)) { dismiss() }
    }
}

struct DiaperEntryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BabySectionHeader(
                        title: "Choose one",
                        subtitle: "“Both” counts toward both wet and dirty totals."
                    )
                }
                Section("Tap once to log") {
                    ForEach(DiaperKind.allCases, id: \.self) { kind in
                        Button {
                            if model.save(Activity(kind: .diaper, startedAt: startedAt, diaperKind: kind)) { dismiss() }
                        } label: {
                            Label(kind.rawValue.capitalized, systemImage: kind == .wet ? "drop" : "circle.hexagongrid")
                                .foregroundStyle(BabyTheme.diaper)
                                .font(.title3.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        }.accessibilityIdentifier("diaper" + kind.rawValue.capitalized)
                    }
                }
                Section("When") { DatePicker("Time", selection: $startedAt) }
            }
            .babyFormStyle()
            .navigationTitle("Diaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .modelErrorAlert(model)
        }
    }
}

struct SleepEntryView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date()
    @State private var endedAt = Date()
    @State private var running = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BabySectionHeader(
                        title: running ? "Start sleep timer" : "Add completed sleep",
                        subtitle: running ? "Stop it from Today when sleep ends." : "Choose both times below."
                    )
                }
                Section("Timing") {
                    Picker("Entry type", selection: $running) {
                        Text("Start timer").tag(true)
                        Text("Completed").tag(false)
                    }
                    .babyChoiceStyle()
                    DatePicker("Started", selection: $startedAt)
                    if !running { DatePicker("Ended", selection: $endedAt, in: startedAt...) }
                }
            }
            .babyFormStyle()
            .navigationTitle("Log sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.save(Activity(
                            kind: .sleep, startedAt: startedAt,
                            endedAt: running ? nil : max(endedAt, startedAt),
                            isRunning: running
                        )) { dismiss() }
                    }
                }
            }
            .modelErrorAlert(model)
        }
    }
}

struct CustomEntryView: View {
    @ObservedObject var model: AppModel
    let tracker: CustomTracker
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date()

    var body: some View {
        NavigationStack {
            Form { DatePicker("Time", selection: $startedAt) }
                .babyFormStyle()
                .navigationTitle(tracker.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if model.save(Activity(
                                kind: .custom, startedAt: startedAt,
                                customTrackerID: tracker.id,
                                customName: tracker.name, customColor: tracker.color
                            )) { dismiss() }
                        }
                    }
                }
                .modelErrorAlert(model)
        }
    }
}
