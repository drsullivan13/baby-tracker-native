import SwiftUI
import BabyTrackerDomain

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var editing: Activity?
    @State private var showDeleted = false
    @State private var showConflicts = false
    @State private var averageDays = 7

    private var selectedActivities: [Activity] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BabyStatistics.defaultTimeZone
        return model.activeActivities.filter { calendar.isDate($0.startedAt, inSameDayAs: model.selectedDay) }
    }

    private var stats: DayStatistics {
        BabyStatistics.dayStatistics(
            activities: model.activeActivities, containing: model.selectedDay, asOf: Date()
        )
    }

    var body: some View {
        List {
            Section {
                DatePicker("Day", selection: $model.selectedDay, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(BabyTheme.feed)
            }
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    BabySectionHeader(
                        title: "Selected day",
                        subtitle: selectedDaySubtitle
                    )
                    HistoryMetric(label: "Bottle volume", value: "\(Int(stats.amountMl.rounded())) ml", detail: String(format: "%.1f fl oz", stats.amountFlOz), color: BabyTheme.feed)
                    HistoryMetric(label: "Feeds", value: "\(stats.feeds)", detail: "Bottle and nursing logs", color: BabyTheme.feed)
                    HistoryMetric(label: "Diapers", value: "\(stats.diaperTotal)", detail: "\(stats.wetDiapers) wet · \(stats.dirtyDiapers) dirty", color: BabyTheme.diaper)
                    HistoryMetric(label: "Sleep", value: durationText(stats.sleepSeconds), detail: "Time overlapping this day", color: BabyTheme.sleep)
                }
                .padding(.vertical, 6)
            }
            Section {
                BabySectionHeader(
                    title: "Daily averages",
                    subtitle: "Whole days only, including days with no logs"
                )
                Picker("Window", selection: $averageDays) { Text("7 days").tag(7); Text("30 days").tag(30) }.babyChoiceStyle()
                AverageRow(average: averages, customAverages: customAverages)
                periodComparison
                FeedingTrend(values: trendValues)
            }
            Section {
                BabySectionHeader(title: "Timeline", subtitle: "Tap to edit, swipe to delete")
                if selectedActivities.isEmpty {
                    BabyEmptyState(
                        symbol: "calendar.badge.clock",
                        title: "No logs this day",
                        message: "Choose another date or add the next event from Today."
                    )
                }
                ForEach(selectedActivities) { activity in
                    Button { editing = activity } label: { ActivityRow(activity: activity) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("historyActivity-\(activity.kind.rawValue)-\(activity.isRunning ? "running" : "completed")")
                        .swipeActions {
                            Button(role: .destructive) { model.setDeleted(activity, deleted: true) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            Section {
                Button {
                    showDeleted = true
                } label: {
                    Label("Recently Deleted (\(model.deletedActivities.count))", systemImage: "trash")
                        .frame(minHeight: 44)
                }
                if !model.dataset.conflicts.isEmpty {
                    Button {
                        showConflicts = true
                    } label: {
                        Label("Review Conflicts (\(model.dataset.conflicts.count))", systemImage: "exclamationmark.bubble")
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .babyFormStyle()
        .navigationTitle("History")
        .sheet(item: $editing) { ActivityEditor(model: model, activity: $0) }
        .sheet(isPresented: $showDeleted) { DeletedRecordsView(model: model) }
        .sheet(isPresented: $showConflicts) { ConflictReviewView(model: model) }
    }

    private var averages: PeriodAverages {
        BabyStatistics.completedAverages(
            activities: model.activeActivities,
            selectedDay: model.selectedDay,
            days: averageDays,
            asOf: Date()
        )
    }

    private var periodComparison: some View {
        let current = averages
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BabyStatistics.defaultTimeZone
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: current.startDate)!
        let previous = BabyStatistics.completedAverages(
            activities: model.activeActivities, selectedDay: previousEnd,
            days: averageDays, asOf: Date()
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text("Compared with the previous \(averageDays) days")
                .font(.headline)
            Text("\(previous.startDate.formatted(date: .abbreviated, time: .omitted)) – \(previous.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(BabyTheme.quietText)
            if current.feeds == 0 || previous.feeds == 0 {
                Text("Log feeds in both periods to compare them.")
            } else {
                Text(changeText(current.feeds - previous.feeds, unit: "feeds/day"))
                Text(changeText(current.amountMl - previous.amountMl, unit: "ml/day of measured bottle volume"))
            }
            Text("Based on logged entries. Missing logs can affect the comparison; nursing volume is not measured.")
                .font(.caption).foregroundStyle(BabyTheme.quietText)
        }.padding(.vertical, 6)
    }

    private func changeText(_ change: Double, unit: String) -> String {
        let rounded = (change * 10).rounded() / 10
        if rounded == 0 { return "No change in \(unit)" }
        return "\(rounded > 0 ? "Up" : "Down") \(abs(rounded).formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private var selectedDaySubtitle: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BabyStatistics.defaultTimeZone
        if calendar.isDateInToday(model.selectedDay) {
            return "Today, through \(Date().formatted(date: .omitted, time: .shortened))"
        }
        return model.selectedDay.formatted(date: .complete, time: .omitted)
    }

    private var customAverages: [CustomAverage] {
        let average = averages
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = BabyStatistics.defaultTimeZone
        let end = calendar.date(byAdding: .day, value: 1, to: average.endDate)!
        let entries = model.activeActivities.filter {
            $0.kind == .custom && $0.customTrackerID != nil &&
            $0.startedAt >= average.startDate && $0.startedAt < end
        }
        return Dictionary(grouping: entries, by: { $0.customTrackerID! }).map { id, values in
            CustomAverage(
                id: id,
                name: values.max(by: { $0.startedAt < $1.startedAt })?.customName ?? "Custom",
                count: Double(values.count) / Double(average.days)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var trendValues: [DayStatistics] {
        BabyStatistics.completedDailyStatistics(
            activities: model.activeActivities,
            selectedDay: model.selectedDay,
            days: averageDays,
            asOf: Date()
        )
    }
}

private struct AverageRow: View {
    let average: PeriodAverages
    let customAverages: [CustomAverage]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible()),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(average.startDate.formatted(date: .abbreviated, time: .omitted)) – \(average.endDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline.weight(.semibold))
            Text("Only completed days in this date range are included.")
                .font(.caption)
                .foregroundStyle(BabyTheme.quietText)
            LazyVGrid(columns: columns, spacing: 12) {
                AverageMetric(label: "Feeds / day", value: String(format: "%.1f", average.feeds))
                AverageMetric(label: "Measured bottle volume / day", value: "\(Int(average.amountMl.rounded())) ml")
                AverageMetric(label: "Wet / day", value: String(format: "%.1f", average.wetDiapers))
                AverageMetric(label: "Dirty / day", value: String(format: "%.1f", average.dirtyDiapers))
                AverageMetric(label: "Sleep / day", value: durationText(average.sleepSeconds))
                AverageMetric(label: "Nursing / day", value: String(format: "%.1f", average.nursingFeeds))
            }
            ForEach(customAverages) { item in
                LabeledContent(item.name, value: String(format: "%.1f / day", item.count))
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CustomAverage: Identifiable {
    let id: UUID
    let name: String
    let count: Double
}

private struct AverageMetric: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(.headline, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(BabyTheme.quietText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryMetric: View {
    let label: String
    let value: String
    let detail: String
    let color: Color
    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.subheadline.weight(.semibold))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.system(.headline, design: .rounded)).monospacedDigit()
                Text(detail).font(.caption2).foregroundStyle(BabyTheme.quietText)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FeedingTrend: View {
    let values: [DayStatistics]

    private var feedScaleMaximum: Int {
        max(1, values.map(\.feeds).max() ?? 0)
    }

    private var bottleScaleMaximum: Double {
        max(1, values.map(\.amountMl).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feeding trend").font(.headline)
            Text("Completed days · feeds and measured bottle volume")
                .font(.caption)
                .foregroundStyle(BabyTheme.quietText)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 14) {
                    FeedingTrendLane(
                        title: "Feed count",
                        scaleLabel: "Scale: 0–\(feedScaleMaximum) feeds",
                        values: values,
                        maximum: Double(feedScaleMaximum),
                        color: BabyTheme.feed
                    ) { day in
                        (Double(day.feeds), "\(day.feeds) feeds")
                    }
                    FeedingTrendLane(
                        title: "Bottle volume",
                        scaleLabel: "Scale: 0–\(Int(bottleScaleMaximum.rounded(.up))) ml",
                        values: values,
                        maximum: bottleScaleMaximum,
                        color: BabyTheme.feed.opacity(0.55)
                    ) { day in
                        (
                            day.amountMl,
                            "\(day.amountMl.formatted(.number.precision(.fractionLength(0...1)))) milliliters"
                        )
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.visible)
        }
        .padding(.vertical, 6)
    }
}

private struct FeedingTrendLane: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let scaleLabel: String
    let values: [DayStatistics]
    let maximum: Double
    let color: Color
    let measurement: (DayStatistics) -> (value: Double, spokenValue: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(scaleLabel)
                    .font(.caption)
                    .foregroundStyle(BabyTheme.quietText)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(values, id: \.day) { day in
                    let reading = measurement(day)
                    VStack(spacing: 4) {
                        Text(reading.value.formatted(.number.precision(.fractionLength(0...1))))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(BabyTheme.quietText)
                        ZStack(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 1)
                            if reading.value > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(height: CGFloat(reading.value / maximum) * 54)
                            }
                        }
                        .frame(height: 54, alignment: .bottom)
                        Text(day.day, format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(BabyTheme.quietText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 120 : 48)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(day.day.formatted(date: .complete, time: .omitted)), \(title), \(reading.spokenValue)"
                    )
                }
            }
        }
        .frame(minWidth: CGFloat(values.count) * 54, alignment: .leading)
    }
}

struct ActivityEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Activity
    @State private var hasEnd: Bool

    init(model: AppModel, activity: Activity) {
        self.model = model
        _draft = State(initialValue: activity)
        _hasEnd = State(initialValue: activity.endedAt != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BabySectionHeader(
                        title: draft.title,
                        subtitle: "Changes stay in the private shared history."
                    )
                }
                Section("Timing") {
                    DatePicker("Started", selection: $draft.startedAt)
                }
                if draft.isRunning {
                    Section {
                        LabeledContent("Status", value: "Running")
                        Text("Stop this timer using the Stop button on Today.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("activityRunningStatus")
                } else if draft.kind == .sleep || (draft.kind == .feed && draft.feedMethod == .breast) || hasEnd {
                    Toggle("Has end time", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ended", selection: Binding(
                            get: { draft.endedAt ?? draft.startedAt },
                            set: { draft.endedAt = $0 }
                        ), in: draft.startedAt...)
                    }
                }
                Section("Details") { details }
                Section {
                    Button("Move to Recently Deleted", role: .destructive) {
                        if model.setDeleted(draft, deleted: true) { dismiss() }
                    }
                    .frame(minHeight: 44)
                }
            }
            .babyFormStyle()
            .navigationTitle("Edit \(draft.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.endedAt = draft.isRunning ? nil : (
                            hasEnd ? max(draft.endedAt ?? draft.startedAt, draft.startedAt) : nil
                        )
                        if model.save(draft, action: .edit) { dismiss() }
                    }
                }
            }
            .modelErrorAlert(model)
        }
    }

    @ViewBuilder private var details: some View {
        switch draft.kind {
        case .feed:
            Picker("Method", selection: Binding($draft.feedMethod, replacingNilWith: .breast)) {
                Text("Breast").tag(FeedMethod.breast)
                Text("Bottle").tag(FeedMethod.bottle)
            }
            .disabled(draft.isRunning)
            .onChange(of: draft.feedMethod) { _, method in
                if method == .bottle {
                    draft.feedSide = nil
                    draft.isRunning = false
                } else {
                    draft.amountMl = nil
                    draft.bottleMilkType = nil
                    draft.feedSide = draft.feedSide ?? .left
                }
            }
            if draft.feedMethod == .breast {
                Picker("Side", selection: Binding($draft.feedSide, replacingNilWith: .left)) {
                    ForEach(FeedSide.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
            } else {
                TextField("Amount (ml)", value: $draft.amountMl, format: .number)
                    .keyboardType(.decimalPad)
                Picker("Bottle milk", selection: Binding($draft.bottleMilkType, replacingNilWith: .breastMilk)) {
                    Text("Breast milk").tag(BottleMilkType.breastMilk)
                    Text("Formula").tag(BottleMilkType.formula)
                }
            }
        case .diaper:
            Picker("Kind", selection: Binding($draft.diaperKind, replacingNilWith: .wet)) {
                ForEach(DiaperKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.babyChoiceStyle()
        case .sleep: EmptyView()
        case .custom:
            TextField("Name", text: Binding($draft.customName, replacingNilWith: "Custom"))
            ColorPicker("Color", selection: Binding(
                get: { Color(hex: draft.customColor ?? "#53AD99") },
                set: { draft.customColor = $0.hex }
            ), supportsOpacity: false)
        }
    }
}

private struct DeletedRecordsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if !model.deletedActivities.isEmpty {
                    Section {
                        Text("Restore a record to return it to Today and History.")
                            .font(.subheadline)
                            .foregroundStyle(BabyTheme.quietText)
                    }
                }
                ForEach(model.deletedActivities) { activity in
                    HStack {
                        ActivityRow(activity: activity)
                        Button("Restore") { model.setDeleted(activity, deleted: false) }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                }
            }
            .babyFormStyle()
            .overlay {
                if model.deletedActivities.isEmpty {
                    ContentUnavailableView(
                        "Nothing deleted",
                        systemImage: "trash",
                        description: Text("Deleted records can be restored from here.")
                    )
                }
            }
            .navigationTitle("Recently Deleted")
            .toolbar { Button("Done") { dismiss() } }
            .modelErrorAlert(model)
        }
    }
}

private struct ConflictReviewView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if !model.dataset.conflicts.isEmpty {
                    Section {
                        Text("Two phones changed the same item independently. Compare the details and choose the version to keep.")
                            .font(.subheadline)
                            .foregroundStyle(BabyTheme.quietText)
                    }
                }
                ForEach(model.dataset.conflicts) { conflict in
                    Section("Choose the version to keep") {
                        ForEach(Array(conflict.versions.enumerated()), id: \.offset) { index, version in
                            Button {
                                model.resolve(conflict, choosing: version)
                            } label: {
                                Group {
                                switch version {
                            case .activity(let activity): ConflictActivityRow(activity: activity)
                            case .tracker(let tracker): ConflictTrackerRow(tracker: tracker)
                                }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .babyFormStyle()
            .overlay {
                if model.dataset.conflicts.isEmpty {
                    ContentUnavailableView(
                        "No conflicts",
                        systemImage: "checkmark.circle",
                        description: Text("Synced changes agree.")
                    )
                }
            }
            .navigationTitle("Review Conflicts")
            .toolbar { Button("Done") { dismiss() } }
            .modelErrorAlert(model)
        }
    }
}

private struct ConflictActivityRow: View {
    let activity: Activity
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(activity.title).font(.body.weight(.semibold)); Spacer(); Text(activity.deleted ? "Deleted" : "Active").font(.caption.bold()).foregroundStyle(activity.deleted ? .red : .green) }
            Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened) + (activity.endedAt.map { " → \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            Text(conflictDetails(activity)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ConflictTrackerRow: View {
    let tracker: CustomTracker
    var body: some View { HStack { Circle().fill(Color(hex: tracker.color)).frame(width: 12, height: 12); Text(tracker.name); Spacer(); Text(tracker.archived ? "Archived" : "Active").font(.caption.bold()) } }
}

private func conflictDetails(_ activity: Activity) -> String {
    switch activity.kind {
    case .feed: return activity.feedMethod == .bottle ? "Bottle · \(activity.amountMl.map { "\(Int($0.rounded())) ml" } ?? "amount not recorded")" : "Breast · \(activity.feedSide?.rawValue.capitalized ?? "side not recorded")"
    case .diaper: return "Diaper · \(activity.diaperKind?.rawValue.capitalized ?? "type not recorded")"
    case .sleep: return "Sleep" + (activity.isRunning ? " · running" : "")
    case .custom: return "Custom · \(activity.customName ?? "Unnamed")"
    }
}

private extension Binding {
    init(_ source: Binding<Value?>, replacingNilWith fallback: Value) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0 })
    }
}
