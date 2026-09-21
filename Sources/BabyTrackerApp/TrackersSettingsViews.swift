import SwiftUI
import BabyTrackerDomain
#if canImport(UIKit)
import UIKit
#endif

struct TrackersView: View {
    @ObservedObject var model: AppModel
    @State private var editing: CustomTracker?
    @State private var creating = false

    var body: some View {
        List {
            Section {
                BabySectionHeader(
                    title: "Make tracking your own",
                    subtitle: "Add a simple one-tap log for routines that matter to your family."
                )
            }
            Section("Your trackers") {
                if model.trackers.isEmpty {
                    BabyEmptyState(
                        symbol: "square.grid.2x2",
                        title: "No custom trackers",
                        message: "Try bath, tummy time, or medicine."
                    )
                }
                ForEach(model.trackers) { tracker in
                    Button { editing = tracker } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color(hex: tracker.color))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tracker.name).font(.body.weight(.semibold))
                                Text("\(todayCount(for: tracker)) today")
                                    .font(.caption)
                                    .foregroundStyle(BabyTheme.quietText)
                            }
                            Spacer()
                            if tracker.archived {
                                Text("Archived")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BabyTheme.quietText)
                            }
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 52)
                    }
                }
            }
        }
        .babyFormStyle()
        .navigationTitle("Trackers")
        .toolbar {
            Button { creating = true } label: { Label("New tracker", systemImage: "plus") }
                .accessibilityLabel("New tracker")
        }
        .sheet(isPresented: $creating) { TrackerEditor(model: model, tracker: nil) }
        .sheet(item: $editing) { TrackerEditor(model: model, tracker: $0) }
    }

    private func todayCount(for tracker: CustomTracker) -> Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = BabyStatistics.defaultTimeZone
        return model.activeActivities.filter { $0.kind == .custom && $0.customTrackerID == tracker.id && calendar.isDate($0.startedAt, inSameDayAs: Date()) }.count
    }
}

private struct TrackerEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let original: CustomTracker?
    @State private var name: String
    @State private var color: Color

    init(model: AppModel, tracker: CustomTracker?) {
        self.model = model
        original = tracker
        _name = State(initialValue: tracker?.name ?? "")
        _color = State(initialValue: Color(hex: tracker?.color ?? "#53AD99"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BabySectionHeader(
                        title: original == nil ? "Create a quick log" : "Update this tracker",
                        subtitle: "The color makes it easy to spot in your history."
                    )
                }
                Section("Details") {
                    TextField("Tracker name", text: $name)
                    ColorPicker("Color", selection: $color, supportsOpacity: false)
                }
                if let original {
                    Section {
                        Button(original.archived ? "Restore Tracker" : "Archive Tracker") {
                            var changed = original
                            changed.name = name
                            changed.color = color.hex
                            changed.archived.toggle()
                            if model.save(changed, action: changed.archived ? .archive : .restoreTracker) { dismiss() }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .babyFormStyle()
            .navigationTitle(original == nil ? "New Tracker" : "Edit Tracker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var tracker = original ?? CustomTracker(name: name, color: color.hex)
                        tracker.name = name
                        tracker.color = color.hex
                        if model.save(tracker) { dismiss() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .modelErrorAlert(model)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sync: NearbySync
    @State private var showPairing = false

    var body: some View {
        List {
            Section {
                BabySectionHeader(
                    title: "Private by design",
                    subtitle: "Your records stay on this phone and a directly paired phone."
                )
            }
            Section("Privacy") {
                Label("No account, analytics, or cloud database", systemImage: "hand.raised.fill")
                Label("Encrypted nearby sharing", systemImage: "lock.shield.fill")
                Text("The database and import folder use complete file protection and request backup exclusion. Apple’s backup settings still need your check.")
                    .font(.footnote)
                    .foregroundStyle(BabyTheme.quietText)
            }
            Section("Local import") {
                Toggle("I verified this app is excluded from cloud backup", isOn: Binding(
                    get: { model.backupAcknowledged },
                    set: { model.backupAcknowledged = $0 }
                ))
                Text("Stage records.json only in Application Support/Imports, then import it here. The staging file is deleted only after a successful transaction.")
                    .font(.caption).foregroundStyle(BabyTheme.quietText)
                Button {
                    model.importStagedFile()
                } label: {
                    Label("Import staged records.json", systemImage: "square.and.arrow.down")
                        .frame(minHeight: 44)
                }
                    .disabled(!model.backupAcknowledged)
            }
            Section("Nearby pair and sync") {
                LabeledContent("Status", value: sync.status)
                if let lastSync = sync.lastSync {
                    LabeledContent("Last exchange") {
                        Text(lastSync, format: .dateTime.month().day().hour().minute())
                    }
                    Text("A previous exchange does not mean the other device is currently nearby or up to date.")
                        .font(.caption).foregroundStyle(BabyTheme.quietText)
                }
                Button {
                    showPairing = true
                } label: {
                    Label(sync.isPaired ? "Manage Paired Device" : "Pair a Device", systemImage: "iphone.radiowaves.left.and.right")
                        .frame(minHeight: 44)
                }
                    .disabled(!model.backupAcknowledged)
                Button {
                    sync.requestSync()
                } label: {
                    Label("Request Sync", systemImage: "arrow.triangle.2.circlepath")
                        .frame(minHeight: 44)
                }
                .disabled(!sync.isPaired)
            }
        }
        .babyFormStyle()
        .navigationTitle("Settings")
        .sheet(isPresented: $showPairing) {
            NavigationStack {
                PairingView(sync: sync)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPairing = false } } }
            }
        }
    }
}

extension Color {
    var hex: String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        #else
        return "#53AD99"
        #endif
    }
}
