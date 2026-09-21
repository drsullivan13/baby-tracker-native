import SwiftUI
import BabyTrackerDomain

@main
struct BabyTrackerApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var sync = NearbySync()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model, sync: sync)
                .preferredColorScheme(.dark)
                .environment(\.timeZone, BabyStatistics.defaultTimeZone)
                .overlay {
                    if scenePhase != .active {
                        ZStack {
                            BabyTheme.background.ignoresSafeArea()
                            Label("Baby Tracker", systemImage: "lock.fill").font(.title2)
                        }
                    }
                }
                .task { configureSync() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        if model.backupAcknowledged { sync.start(); sync.requestSync() }
                    case .background:
                        sync.stop()
                    default: break
                    }
                }
                .onChange(of: model.backupAcknowledged) { _, checked in
                    if checked { sync.start(); sync.requestSync() }
                    else { sync.stop() }
                }
                .onChange(of: sync.errorMessage) { _, message in
                    if let message { model.errorMessage = message }
                }
        }
    }

    private func configureSync() {
        sync.snapshotProvider = { [weak model] in
            guard let model else { throw AppModelError.storeUnavailable }
            return try model.snapshotData()
        }
        sync.snapshotReceiver = { [weak model] data in
            guard let model else { throw AppModelError.storeUnavailable }
            try model.receiveSnapshot(data)
        }
        model.afterLocalSave = { [weak sync] in sync?.requestSync() }
        if scenePhase == .active && model.backupAcknowledged {
            sync.start()
            sync.requestSync()
        }
    }
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var sync: NearbySync

    var body: some View {
        Group {
            if model.backupAcknowledged { mainTabs }
            else { PrivacySetupView(model: model) }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack { DashboardView(model: model) }
                .tabItem { Label("Today", systemImage: "house.fill") }
            NavigationStack { HistoryView(model: model) }
                .tabItem { Label("History", systemImage: "calendar") }
            NavigationStack { TrackersView(model: model) }
                .tabItem { Label("Trackers", systemImage: "square.grid.2x2") }
            NavigationStack { SettingsView(model: model, sync: sync) }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(BabyTheme.feed)
        .toolbarBackground(BabyTheme.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .safeAreaInset(edge: .top) {
            if let message = model.errorMessage {
                HStack(alignment: .top, spacing: 12) {
                    Label(message, systemImage: "exclamationmark.circle").font(.callout)
                    Spacer(minLength: 0)
                    Button { model.errorMessage = nil } label: {
                        Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Dismiss error")
                }
                .padding(12).background(BabyTheme.card).foregroundStyle(BabyTheme.diaper)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                HStack {
                    Text(notice).font(.callout)
                    if model.undoActivity != nil { Button("Undo") { model.undoDelete() }.bold().frame(minWidth: 44, minHeight: 44) }
                    Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Dismiss notification")
                }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal)
                    .padding(.bottom, 60)
                    .accessibilityElement(children: .contain)
            }
        }
    }
}

private struct PrivacySetupView: View {
    @ObservedObject var model: AppModel
    @State private var verified = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Image("BabyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("Baby Tracker logo")
                    VStack(alignment: .leading, spacing: 10) {
                        Text("A private little record.")
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                        Text("Made for blurry nights and one-handed logging.")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(BabyTheme.feed)
                        Text("Feeds, diapers, sleep, and everyday moments stay on your phones. Sharing happens only when both apps are open nearby.")
                            .foregroundStyle(BabyTheme.quietText)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Label("No cloud database or analytics", systemImage: "externaldrive")
                        Label("Encrypted nearby sharing", systemImage: "iphone.radiowaves.left.and.right")
                        Label("No export or cloud recovery", systemImage: "lock")
                    }.babyCard()
                    BabySectionHeader(title: "Before adding real entries", subtitle: "This one-time check keeps private history out of iCloud Backup.")
                    Text("Check this phone’s iCloud Backup settings:")
                    VStack(alignment: .leading, spacing: 12) {
                        backupStep(1, "Open Settings and tap your name.")
                        backupStep(2, "Tap iCloud, then Storage (or Manage Account Storage).")
                        backupStep(3, "Tap Backups, then select this iPhone’s name.")
                        backupStep(4, "Find Baby Tracker in the backup list. Tap Show All Apps if needed.")
                        backupStep(5, "Turn off Baby Tracker and confirm Turn Off.")
                    }
                    .babyCard()
                    Text("Confirming Turn Off removes any existing cloud backup for this app. It does not remove entries stored on your phone.")
                    DisclosureGroup("Can’t find Baby Tracker?") {
                        Text("The app may not appear until the backup list has loaded. An absent switch does not confirm backup is off. Keep this app empty and leave the acknowledgment off until you can verify its setting, or verify that iCloud Backup is off for this device.")
                            .font(.callout).padding(.top, 8)
                    }
                    .tint(BabyTheme.sleep)
                    Link("View Apple’s iCloud Backup instructions", destination: URL(string: "https://support.apple.com/en-us/108922")!)
                        .foregroundStyle(BabyTheme.feed)
                    Text("The app requests backup exclusion, but cannot enforce or verify Apple’s backup settings. Losing both phone copies means losing the history.")
                        .font(.footnote).foregroundStyle(BabyTheme.quietText)
                    Toggle(isOn: $verified) {
                        Text("I checked: cloud backup is off for this app")
                            .font(.body.weight(.semibold))
                    }
                    .tint(BabyTheme.sleep)
                    .frame(minHeight: 52)
                        .accessibilityIdentifier("privacyAcknowledgment")
                    Button("Start private tracking") { model.backupAcknowledged = true }
                        .buttonStyle(BabyPrimaryButtonStyle(color: BabyTheme.feed))
                        .disabled(!verified || model.store == nil)
                        .accessibilityIdentifier("startTracking")
                    if let error = model.errorMessage { Text(error).foregroundStyle(.orange) }
                }.padding(24)
            }
            .babyScreenBackground()
            .navigationTitle("Baby Tracker")
        }
    }

    private func backupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(BabyTheme.background)
                .frame(width: 28, height: 28)
                .background(BabyTheme.feed, in: Circle())
                .accessibilityHidden(true)
            Text(text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}
