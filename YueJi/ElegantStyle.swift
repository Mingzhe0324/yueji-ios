import SwiftUI
import UIKit
import Charts

/// Clean, elegant presentation pieces shared across the app: cards, icon tiles, row labels,
/// avatars, empty and loading states, the budget gauge and the spending trend chart.
/// Presentation only; no ledger behaviour lives here. Motion is calm and short, uses the
/// shared `YueJiMotion` springs, and honours Reduce Motion and the "playfulAnimations"
/// setting (shown in Settings as "Animations").
enum ElegantMotion {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "playfulAnimations") as? Bool ?? true }
}

/// The tone of an empty or status state. It picks a fitting symbol; there is no character.
enum IslandMood: String { case happy, excited, worried, sad, sleepy }

// MARK: - Cards and buttons

/// A white card with a hairline edge and a soft, low shadow, as in the reference designs.
/// `glow` adds the warm peach light in the top corner used by the hero card.
struct ElegantCard: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 22
    var glow = false
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(IslandTheme.card)
                    .overlay {
                        if glow {
                            RadialGradient(colors: [IslandTheme.glow, IslandTheme.glow.opacity(0)],
                                           center: .topTrailing, startRadius: 0, endRadius: 320)
                        }
                    }
                    .clipShape(shape)
            }
            .overlay(shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.08 : 0.04), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.06), radius: 14, y: 6)
    }
}

extension View {
    func elegantCard(padding: CGFloat = 16, radius: CGFloat = 22, glow: Bool = false) -> some View {
        modifier(ElegantCard(padding: padding, radius: radius, glow: glow))
    }
}

/// Cards rise gently into place the first time a page appears, a few frames apart.
/// One-shot; skipped with Reduce Motion or Animations off (as in UI tests).
struct ElegantEntrance: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        let still = shown || reduceMotion || !ElegantMotion.enabled
        return content
            .opacity(still ? 1 : 0)
            .offset(y: still ? 0 : 14)
            .task {
                guard !shown else { return }
                guard !reduceMotion, ElegantMotion.enabled else { shown = true; return }
                do { try await Task.sleep(for: .milliseconds(16 + 45 * index)) } catch { shown = true; return }
                withAnimation(YueJiMotion.entrance) { shown = true }
            }
    }
}

/// Subtle press feedback for cards and tiles: a slight dip and dim that springs back.
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

/// A small capsule label for amounts and filters ("Left RM 734", "Budget RM 2,000").
struct ElegantChip: View {
    let title: String
    var value: String? = nil
    var tint: Color = .primary
    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            if let value { Text(value).fontWeight(.semibold).foregroundStyle(tint).monospacedDigit() }
        }
        .font(.subheadline)
        .lineLimit(1).minimumScaleFactor(0.8)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(0.04), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Icons, rows and avatars

/// A soft tinted icon tile, or a solid one when `filled`.
struct IslandIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 44
    var filled = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(filled ? Color.white : color)
            .frame(width: size, height: size)
            .background {
                if filled { shape.fill(color.gradient) } else { shape.fill(color.opacity(scheme == .dark ? 0.22 : 0.12)) }
            }
    }
}

/// A list-row label with an icon tile, for links and tools.
struct IslandRowLabel: View {
    let title: String
    let symbol: String
    var color: Color = IslandPalette.leaf
    var body: some View {
        HStack(spacing: 12) {
            IslandIconTile(symbol: symbol, color: color, size: 32, filled: true)
                .accessibilityHidden(true)
            Text(title).foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }
}

/// A round avatar with a stable palette colour per name and a check once settled.
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

/// An empty state: a quiet symbol, a title, a message and optional actions, fading in gently.
struct IslandEmptyState<Actions: View>: View {
    let title: String
    let message: String?
    let mood: IslandMood
    let actions: Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
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
        let still = shown || reduceMotion || !ElegantMotion.enabled
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(IslandTheme.accent)
                .frame(width: 60, height: 60)
                .background(Circle().fill(IslandTheme.accent.opacity(0.08)))
                .scaleEffect(still ? 1 : 0.85)
                .accessibilityHidden(true)
            Text(title).font(.headline).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            actions.padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 12)
        .opacity(still ? 1 : 0).offset(y: still ? 0 : 8)
        .accessibilityElement(children: .contain)
        .task {
            guard !shown else { return }
            guard !reduceMotion, ElegantMotion.enabled else { shown = true; return }
            do { try await Task.sleep(for: .milliseconds(16)) } catch { shown = true; return }
            withAnimation(YueJiMotion.entrance) { shown = true }
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
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 5)
                .accessibilityHidden(true)
            ProgressView().controlSize(.regular)
            Text(tr("正在读取账本", "Loading ledger", "Memuatkan lejar"))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("正在读取账本", "Loading ledger", "Memuatkan lejar"))
    }
}

// MARK: - Budget gauge

/// A semicircle gauge with a teal-to-peach arc that sweeps in, like the reference summary card.
/// `fraction` is the share of the budget used; above 1 the arc stays full and turns `tint`.
struct BudgetGauge: View {
    let fraction: Double
    var overTint: Color = IslandPalette.coral
    var lineWidth: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0
    private var target: Double { min(max(fraction, 0), 1) }
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let diameter = max(1, width - lineWidth - 20)
            let center = CGPoint(x: width / 2, y: proxy.size.height)
            ZStack {
                ForEach(0..<25, id: \.self) { index in
                    Capsule().fill(Color.primary.opacity(index % 6 == 0 ? 0.22 : 0.10))
                        .frame(width: 2, height: index % 6 == 0 ? 8 : 5)
                        .offset(y: -(diameter / 2 + lineWidth / 2 + 8))
                        .rotationEffect(.degrees(-90 + Double(index) * 7.5))
                        .position(center)
                }
                Circle().trim(from: 0.5, to: 1)
                    .stroke(Color.primary.opacity(0.07), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .position(center)
                Circle().trim(from: 0.5, to: 0.5 + 0.5 * shown)
                    .stroke(arcStyle, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .opacity(shown > 0.001 ? 1 : 0)
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear { sweep() }
        .onChange(of: fraction) { _, _ in sweep() }
    }
    private var arcStyle: AnyShapeStyle {
        if fraction > 1 { return AnyShapeStyle(overTint.gradient) }
        return AnyShapeStyle(LinearGradient(colors: [IslandTheme.teal, IslandTheme.peach], startPoint: .leading, endPoint: .trailing))
    }
    private func sweep() {
        if reduceMotion || !ElegantMotion.enabled { shown = target; return }
        withAnimation(YueJiMotion.meter) { shown = target }
    }
}

// MARK: - Spending trend chart

struct SpendingTrendPoint: Identifiable, Equatable {
    let month: Date
    let cents: Int
    var id: String { monthKey(month) }
}

/// Six months of personal spending as soft bars; the selected month glows with the gradient
/// and carries a value tooltip. Tapping a bar selects that month.
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
                    width: .ratio(0.56))
                .cornerRadius(8)
                .foregroundStyle(isSelected
                    ? AnyShapeStyle(LinearGradient(colors: [IslandTheme.peach, IslandTheme.teal], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color.primary.opacity(0.08)))
                .annotation(position: .top, spacing: 6) {
                    if isSelected && !hidden && point.cents > 0 {
                        Text(money(point.cents))
                            .font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(IslandTheme.onAccent)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Capsule().fill(IslandTheme.accent))
                    }
                }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 4])).foregroundStyle(Color.primary.opacity(0.08))
                // Hidden amounts keep the grid but blank the values.
                AxisValueLabel().foregroundStyle(Color.secondary.opacity(hidden ? 0 : 1))
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.secondary) }
        }
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
        .frame(height: 190)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: selectedKey)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: points)
        .onAppear {
            guard !grown else { return }
            if reduceMotion || !ElegantMotion.enabled { grown = true } else { withAnimation(YueJiMotion.meter) { grown = true } }
        }
    }
}

// MARK: - Category donut

/// A slim donut of this month's category shares with the total in the middle. Decorative:
/// the rows beneath it carry the same amounts for VoiceOver.
struct CategoryDonut: View {
    struct Slice: Identifiable, Equatable {
        let category: String
        let cents: Int
        let color: Color
        var id: String { category }
    }
    let slices: [Slice]
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        let still = shown || reduceMotion || !ElegantMotion.enabled
        ZStack {
            Chart(slices) { slice in
                SectorMark(angle: .value("Spent", slice.cents), innerRadius: .ratio(0.7), angularInset: 1.5)
                    .cornerRadius(4)
                    .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .rotationEffect(.degrees(still ? 0 : -40))
            VStack(spacing: 2) {
                Text(tr("本月", "This month", "Bulan ini")).font(.caption).foregroundStyle(.secondary)
                Text(money(total)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: 96)
        }
        .frame(width: 156, height: 156)
        .scaleEffect(still ? 1 : 0.9)
        .opacity(still ? 1 : 0)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: slices)
        .accessibilityHidden(true)
        .task {
            guard !shown else { return }
            guard !reduceMotion, ElegantMotion.enabled else { shown = true; return }
            do { try await Task.sleep(for: .milliseconds(120)) } catch { shown = true; return }
            withAnimation(YueJiMotion.meter) { shown = true }
        }
    }
}
