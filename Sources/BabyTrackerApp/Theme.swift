import SwiftUI
import BabyTrackerDomain
#if canImport(UIKit)
import UIKit
#endif

enum BabyTheme {
    static let background = Color(red: 7 / 255, green: 19 / 255, blue: 34 / 255)
    static let card = Color(red: 17 / 255, green: 38 / 255, blue: 57 / 255)
    static let raised = Color(red: 25 / 255, green: 49 / 255, blue: 69 / 255)
    static let outline = Color.white.opacity(0.09)
    static let feed = Color(red: 1, green: 129 / 255, blue: 112 / 255)
    static let diaper = Color(red: 241 / 255, green: 190 / 255, blue: 99 / 255)
    static let sleep = Color(red: 86 / 255, green: 197 / 255, blue: 178 / 255)
    static let quietText = Color(red: 181 / 255, green: 198 / 255, blue: 211 / 255)
    static let wash = LinearGradient(
        colors: [Color(red: 12 / 255, green: 31 / 255, blue: 50 / 255), background],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func color(for kind: ActivityKind) -> Color {
        switch kind {
        case .feed: return feed
        case .diaper: return diaper
        case .sleep, .custom: return sleep
        }
    }
}

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(BabyTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(BabyTheme.outline, lineWidth: 1)
            }
    }
}

extension View {
    func babyChoiceStyle() -> some View { modifier(BabyChoiceModifier()) }
    func babyCard() -> some View { modifier(CardModifier()) }
    func babyScreenBackground() -> some View {
        background(BabyTheme.wash.ignoresSafeArea())
    }
    func babyFormStyle() -> some View {
        scrollContentBackground(.hidden)
            .background(BabyTheme.background)
    }
    func modelErrorAlert(_ model: AppModel) -> some View {
        alert("Baby Tracker", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

private struct BabyChoiceModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize { content.pickerStyle(.menu) }
        else { content.pickerStyle(.segmented) }
    }
}

struct BabySectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(BabyTheme.quietText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct BabyPrimaryButtonStyle: ButtonStyle {
    var color = BabyTheme.feed
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(BabyTheme.background)
            .background(color.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
    }
}

struct BabyEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(BabyTheme.sleep)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(BabyTheme.quietText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(clean, radix: 16) ?? 0x53AD99
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

extension Activity {
    var title: String {
        switch kind {
        case .feed:
            if feedMethod == .bottle {
                let amount = amountMl.map { " · \(Int($0.rounded())) ml" } ?? ""
                return "Bottle\(amount)"
            }
            return "Breastfeed\(feedSide.map { " · \($0.rawValue.capitalized)" } ?? "")"
        case .diaper: return "\(diaperKind?.rawValue.capitalized ?? "") diaper"
        case .sleep: return "Sleep"
        case .custom: return customName ?? "Custom"
        }
    }

    var symbol: String {
        switch kind {
        case .feed: return "drop.fill"
        case .diaper: return "circle.hexagongrid.fill"
        case .sleep: return "moon.stars.fill"
        case .custom: return "sparkles"
        }
    }
}

func durationText(_ interval: TimeInterval, includeSeconds: Bool = false) -> String {
    let total = max(0, Int(interval))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if includeSeconds { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}
