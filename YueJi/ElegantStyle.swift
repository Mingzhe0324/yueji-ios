import SwiftUI
import UIKit
import Charts

/// Shared presentation pieces in Apple's own style: flat grouped panels, glass icon buttons,
/// icon tiles, row labels, avatars, empty and loading states, and the spending trend chart.
/// Presentation only; no ledger behaviour lives here. Motion is the system's, and the few
/// content animations honour Reduce Motion and the "playfulAnimations" setting (shown in
/// Settings as "Animations").
enum ElegantMotion {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "playfulAnimations") as? Bool ?? true }
}

/// The tone of an empty or status state. It picks a fitting symbol; there is no character.
enum IslandMood: String { case happy, excited, worried, sad, sleepy }

// MARK: - Panels and buttons

/// A panel exactly like the system's grouped sections in iOS 26/27: the secondary grouped
/// background with continuous corners, flat, with no outline or shadow.
struct ElegantCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 26
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IslandTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func elegantCard(padding: CGFloat = 16, radius: CGFloat = 26) -> some View {
        modifier(ElegantCard(padding: padding, radius: radius))
    }
}

/// A round icon button. On iOS 26 and later it is Apple's own Liquid Glass circle, so its
/// press, glow and morphing are exactly the system's; otherwise a soft tinted circle.
struct GlassIconButton: View {
    let symbol: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            Button(action: action) {
                Image(systemName: symbol).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .frame(minWidth: 44, minHeight: 44)
        } else {
            Button(action: action) {
                Image(systemName: symbol).font(.subheadline.weight(.semibold))
                    .foregroundStyle(IslandTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(IslandTheme.accent.opacity(scheme == .dark ? 0.16 : 0.08)))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(ElegantPressStyle())
        }
    }
}

/// Subtle press feedback for tappable panels: a slight dip and dim that springs back.
struct ElegantPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ElegantPressBody(configuration: configuration)
    }
}

private struct ElegantPressBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(reduceMotion ? nil : YueJiMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Icons, rows and avatars

/// Category and transaction icons as Apple Card draws them: a white symbol on a coloured
/// circle. `filled` gives the rounded-square tile of Settings rows instead.
struct IslandIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 44
    var filled = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * (filled ? 0.44 : 0.42), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(color.gradient)
                } else {
                    Circle().fill(color.gradient)
                }
            }
    }
}

/// A list-row label with a Settings-style icon tile, for links and tools.
struct IslandRowLabel: View {
    let title: String
    let symbol: String
    var color: Color = IslandPalette.leaf
    var body: some View {
        HStack(spacing: 12) {
            IslandIconTile(symbol: symbol, color: color, size: 30, filled: true)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}

/// A round monogram avatar with a stable palette colour per name and a check once settled.
struct IslandAvatar: View {
    let name: String
    var settled = false
    var size: CGFloat = 44
    private var color: Color {
        let colors = [IslandPalette.mint, IslandPalette.sky, IslandPalette.lavender, IslandPalette.berry,
                      IslandPalette.coral, IslandPalette.pumpkin, IslandPalette.lagoon]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return colors[hash % colors.count]
    }
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
            .overlay(alignment: .bottomTrailing) {
                if settled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: size * 0.34, weight: .bold))
                        .foregroundStyle(.white, IslandPalette.mint)
                        .offset(x: 3, y: 3)
                }
            }
    }
}

// MARK: - Empty and loading states

/// An empty state, drawn by the system's own `ContentUnavailableView` exactly as in Apple's
/// apps: a symbol, a title, a message and optional actions.
struct IslandEmptyState<Actions: View>: View {
    let title: String
    let message: String?
    let mood: IslandMood
    let actions: Actions
    init(title: String, message: String? = nil, mood: IslandMood = .sleepy, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.message = message; self.mood = mood; self.actions = actions()
    }
    private var symbol: String {
        switch mood {
        case .sleepy: return "tray"
        case .happy: return "sparkles"
        case .excited: return "checkmark.seal"
        case .worried: return "magnifyingglass"
        case .sad: return "xmark.circle"
        }
    }
    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            if let message { Text(message) }
        } actions: {
            actions
        }
    }
}
extension IslandEmptyState where Actions == EmptyView {
    init(title: String, message: String? = nil, mood: IslandMood = .sleepy) {
        self.init(title: title, message: message, mood: mood) { EmptyView() }
    }
}

/// Shown while the ledger loads when the opening is turned off.
struct YueJiLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("YueJiLogo").resizable().scaledToFit().frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .accessibilityHidden(true)
            ProgressView().controlSize(.regular)
            Text(tr("正在读取账本", "Loading ledger", "Memuatkan lejar"))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("正在读取账本", "Loading ledger", "Memuatkan lejar"))
    }
}

// MARK: - Spending trend chart

struct SpendingTrendPoint: Identifiable, Equatable {
    let month: Date
    let cents: Int
    var id: String { monthKey(month) }
}

/// Six months of personal spending as Swift Charts bars in the app tint, as in Apple's
/// Health and Screen Time: the selected month is solid with its value above, the others
/// lighter. Tapping a bar selects that month.
struct SpendingTrendChart: View {
    let points: [SpendingTrendPoint]
    let selected: Date
    var hidden = false
    var onSelect: (Date) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    private func label(_ month: Date) -> String {
        month.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: AppLanguage.localeID)))
    }
    var body: some View {
        let selectedKey = monthKey(selected)
        Chart(points) { point in
            let isSelected = point.id == selectedKey
            BarMark(x: .value("Month", label(point.month)),
                    y: .value("Spent", grown || reduceMotion ? Double(point.cents) / 100 : 0),
                    width: .ratio(0.6))
                .cornerRadius(6)
                .foregroundStyle(isSelected ? IslandTheme.accent : IslandTheme.accent.opacity(0.28))
                .annotation(position: .top, spacing: 4) {
                    if isSelected && !hidden && point.cents > 0 {
                        Text(money(point.cents))
                            .font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
        }
        // Hidden amounts hide the value axis; the bars keep their shape.
        .chartYAxis(hidden ? .hidden : .automatic)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let x = location.x - geometry[plot].origin.x
                        guard let name: String = proxy.value(atX: x),
                              let point = points.first(where: { label($0.month) == name }) else { return }
                        FeedbackHaptics.selection()
                        onSelect(point.month)
                    }
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 180)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: selectedKey)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: points)
        .onAppear {
            guard !grown else { return }
            if reduceMotion || !ElegantMotion.enabled { grown = true } else { withAnimation(YueJiMotion.meter) { grown = true } }
        }
    }
}
