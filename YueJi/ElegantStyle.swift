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

// MARK: - Spending by merchant

/// The colours of a category's merchant split, in a fixed order, largest merchant first:
/// Apple's system teal, orange, indigo, pink and purple. Red and green keep their spending
/// and income meaning. In dark mode teal and orange step down (hue held) to sit with the
/// others on the dark card. The order passes the dataviz palette checks in both modes for
/// every pair of sectors that can touch, the wrap-around to the first included, so they
/// stay apart with colour blindness too. "Other" is a recessive grey.
enum MerchantPalette {
    static let slots: [Color] = [
        dynamic(light: 0x00C3D0, dark: 0x03A6B1),
        dynamic(light: 0xFF8D28, dark: 0xD87403),
        dynamic(light: 0x6155F5, dark: 0x6D7CFF),
        dynamic(light: 0xFF2D55, dark: 0xFF375F),
        dynamic(light: 0xCB30E0, dark: 0xDB34F2),
    ]
    static let other = dynamic(light: 0x8E8E93, dark: 0x48484A)
    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) })
    }
    private static func rgb(_ value: Int) -> UIColor {
        UIColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

/// One merchant's part of a category's month: what it cost me in that category, over how
/// many payments, and its colour. The last slice may be "Other", the merchants past the
/// fifth folded together.
struct MerchantSlice: Identifiable, Equatable {
    /// The merchant's key, or "" for "Other" (no merchant's key is empty).
    let id: String
    /// The merchants it covers: its own key, or every key folded into "Other".
    let merchants: Set<String>
    let name: String
    let cents: Int
    let payments: Int
    let color: Color

    /// Payments group by merchant name, ignoring case and spacing.
    static func key(for entry: Expense) -> String { entry.merchantKey }

    /// A category's month by merchant, largest first: the top five in the palette's order,
    /// then the rest folded into one grey "Other", so the donut never needs a sixth hue.
    /// The amounts are my share in the category, so they add up to its total.
    static func split(_ entries: [Expense], category: String) -> [MerchantSlice] {
        var groups: [String: (name: String, cents: Int, payments: Int)] = [:]
        for entry in entries {
            let cents = entry.personalAmount(category: category)
            guard cents > 0 else { continue }
            let id = Self.key(for: entry)
            var group = groups[id] ?? (name: entry.displayName, cents: 0, payments: 0)
            group.cents += cents
            group.payments += 1
            groups[id] = group
        }
        let ranked = groups.sorted {
            $0.value.cents == $1.value.cents ? $0.value.name < $1.value.name : $0.value.cents > $1.value.cents
        }
        let palette = MerchantPalette.slots
        var slices = ranked.prefix(palette.count).enumerated().map { index, merchant in
            MerchantSlice(id: merchant.key, merchants: [merchant.key], name: merchant.value.name,
                          cents: merchant.value.cents, payments: merchant.value.payments, color: palette[index])
        }
        let rest = ranked.dropFirst(palette.count)
        if !rest.isEmpty {
            let count = rest.count
            slices.append(MerchantSlice(
                id: "", merchants: Set(rest.map { $0.key }),
                name: tr("其他 \(count) 家商户", count == 1 ? "1 other merchant" : "\(count) other merchants", "\(count) peniaga lain"),
                cents: rest.reduce(0) { $0 + $1.value.cents }, payments: rest.reduce(0) { $0 + $1.value.payments },
                color: MerchantPalette.other))
        }
        return slices
    }
}

/// A category's month split by merchant, drawn like the Overview's donut: one rounded sector
/// per merchant in the merchant palette. Tapping a sector selects it (tap it again, or the
/// middle, to clear): the others fade and the middle shows its share. Decorative for
/// VoiceOver; the merchant rows carry the same figures and the same selection.
struct MerchantDonutChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let slices: [MerchantSlice]
    @Binding var selection: String?
    var size: CGFloat = 132
    private var total: Int { slices.reduce(0) { $0 + $1.cents } }
    var body: some View {
        Chart(slices) { slice in
            SectorMark(angle: .value("Spent", Double(slice.cents) / 100),
                       innerRadius: .ratio(0.6), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(slice.color)
                .opacity(selection == nil || selection == slice.id ? 1 : 0.3)
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        select(at: location, in: geometry[plot])
                    }
            }
        }
        .overlay {
            if let selected = slices.first(where: { $0.id == selection }) {
                Text(share(selected.cents))
                    .font(.headline).monospacedDigit()
                    .foregroundStyle(.primary)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: slices)
        .animation(reduceMotion ? nil : YueJiMotion.standard, value: selection)
        .accessibilityHidden(true)
    }
    private func share(_ cents: Int) -> String {
        String(format: "%.0f%%", Double(cents) / Double(max(total, 1)) * 100)
    }
    /// The sector under a tap on the ring; the middle and the corners clear the selection.
    private func select(at location: CGPoint, in plot: CGRect) {
        let dx = location.x - plot.midX, dy = location.y - plot.midY
        let radius = min(plot.width, plot.height) / 2
        let distance = (dx * dx + dy * dy).squareRoot()
        var picked: String?
        if total > 0, distance <= radius, distance >= radius * 0.5 {
            // Sectors run clockwise from twelve o'clock, in the order of `slices`.
            var angle = atan2(Double(dx), Double(-dy))
            if angle < 0 { angle += 2 * .pi }
            var remaining = angle / (2 * .pi) * Double(total)
            for slice in slices {
                remaining -= Double(slice.cents)
                if remaining < 0 { picked = slice.id; break }
            }
        }
        let next = picked == selection ? nil : picked
        guard next != selection else { return }
        FeedbackHaptics.selection()
        withAnimation(reduceMotion ? nil : YueJiMotion.standard) { selection = next }
    }
}
