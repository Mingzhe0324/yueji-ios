import SwiftUI
import UIKit
import Charts

/// Shared presentation pieces in Apple's own style: flat grouped panels, glass icon buttons,
/// icon tiles, row labels, avatars, dashboard section headers and share chips, empty and
/// loading states, and the spending charts.
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
/// press, glow and morphing are exactly the system's; otherwise a soft tinted circle. A
/// changed symbol swaps with the system's replace effect.
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
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .frame(minWidth: 44, minHeight: 44)
        } else {
            Button(action: action) {
                Image(systemName: symbol).font(.subheadline.weight(.semibold))
                    .foregroundStyle(IslandTheme.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(IslandTheme.accent.opacity(scheme == .dark ? 0.16 : 0.08)))
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(ElegantPressStyle())
        }
    }
}

/// A round action with its name underneath, like the quick actions of the Mobile Banking
/// app and the contact actions of Messages in the iOS 27 Builder kit: a Liquid Glass circle
/// on iOS 26 and later, a soft tinted circle otherwise. VoiceOver reads it as one button
/// named by its caption, and tapping the caption runs the action too.
struct QuickActionButton: View {
    let title: String
    let symbol: String
    var tint: Color = IslandTheme.accent
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(spacing: 7) {
            circle
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(enabled ? Color.primary : Color.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.8)
                .accessibilityHidden(true)
                .onTapGesture { if enabled { action() } }
        }
        .frame(maxWidth: .infinity)
    }
    private var icon: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(enabled ? tint : Color.secondary)
            .frame(width: 30, height: 30)
    }
    @ViewBuilder private var circle: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            Button(action: action) { icon }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel(title)
        } else {
            Button(action: action) {
                icon.frame(width: 54, height: 54)
                    .background(Circle().fill(tint.opacity(scheme == .dark ? 0.22 : 0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(ElegantPressStyle())
            .accessibilityLabel(title)
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

/// Category and transaction icons as the kit's Mobile Banking app draws its cards: the
/// symbol in the category's colour on a rounded-square tile tinted with that colour.
/// `filled` gives the solid tile with a white symbol of Settings rows instead.
struct IslandIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 44
    var filled = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    /// Stronger on dark cards, as in the kit, and with Increase Contrast.
    private var tintOpacity: Double {
        (scheme == .dark ? 0.24 : 0.14) + (contrast == .increased ? 0.12 : 0)
    }
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * (filled ? 0.44 : 0.42), weight: .semibold))
            .foregroundStyle(filled ? Color.white : color)
            .frame(width: size, height: size)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(color.gradient)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(tintOpacity))
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

// MARK: - Dashboard sections

/// A section heading as the kit's Mobile Banking app sets them ("Cards", "Other"): the name
/// in bold at the leading edge and, when there is more to see, a quiet action such as
/// "View all" at the trailing edge. Keeps the case it is given.
struct DashboardSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: () -> Void = {}
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 12)
            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle).font(.body).foregroundStyle(.secondary)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(actionTitle + tr("：", ": ", ": ") + title)
            }
        }
        .textCase(nil)
    }
}

/// A category's share of the month, as the chips under the kit's Mobile Banking expenses
/// card: "45% Food" beside a dot of the category's colour, on a capsule tinted with it.
struct CategoryShareChip: View {
    let text: String
    let color: Color
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).lineLimit(1)
        }
        .font(.footnote.weight(.semibold)).monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(color.opacity(scheme == .dark ? 0.22 : 0.12), in: Capsule())
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
/// Health and Screen Time and the bar chart of the iOS 27 Builder kit: the selected month
/// is solid with its value above, the others lighter, and a dashed line marks the average
/// of the months with spending. Tapping a bar selects that month.
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
    /// In ringgit, like the bars; none until two months have spending.
    private var average: Double? {
        let spent = points.map(\.cents).filter { $0 > 0 }
        guard spent.count >= 2 else { return nil }
        return Double(spent.reduce(0, +)) / Double(spent.count) / 100
    }
    var body: some View {
        let selectedKey = monthKey(selected)
        Chart {
            ForEach(points) { point in
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
            if let average = average {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.secondary)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        // Hidden amounts keep the line but not its value.
                        Text(hidden ? tr("平均", "Avg", "Purata") : tr("平均 ", "Avg ", "Purata ") + money(Int((average * 100).rounded())))
                            .font(.caption2.weight(.medium)).monospacedDigit()
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

// MARK: - Spending by category

struct CategorySlice: Identifiable, Equatable {
    let category: String
    let cents: Int
    let color: Color
    var id: String { category }
}

/// Where the month's spending went, as the donut beside the expenses card's amount in the
/// kit's Mobile Banking app: a thick ring with one rounded sector per category in the
/// category's colour, nothing in the middle. Decorative for VoiceOver; the card's amount
/// and the category rows carry the same figures.
struct SpendingDonutChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let slices: [CategorySlice]
    var size: CGFloat = 116
    var body: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value("Spent", Double(slice.cents) / 100),
                       innerRadius: .ratio(0.6), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(slice.color)
        }
        .chartLegend(.hidden)
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: slices)
        .accessibilityHidden(true)
    }
}
