import SwiftUI

/// Cartoon feedback pieces for the Moon Island theme: confetti, companion empty
/// states and the logging streak. Presentation only; no ledger behaviour lives here.
/// Motion honours Reduce Motion and the "playfulAnimations" setting.
enum IslandPlayful {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "playfulAnimations") as? Bool ?? true }
    static let confetti: [Color] = [
        IslandTheme.sun, IslandTheme.accent, Color(red: 0.48, green: 0.86, blue: 0.69),
        Color(red: 1, green: 0.55, blue: 0.45), Color(red: 0.55, green: 0.72, blue: 1), Color(red: 1, green: 0.66, blue: 0.80)
    ]
}

// MARK: - Confetti

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let color: Color
    let shape: Int
    let burst: CGSize
    let fall: CGFloat
    let spin: Double
    let flip: Double
    let size: CGFloat
    static func random(spread: CGFloat) -> ConfettiPiece {
        let angle = CGFloat.random(in: -CGFloat.pi * 0.95 ... -CGFloat.pi * 0.05)
        let distance = CGFloat.random(in: spread * 0.35 ... spread)
        return ConfettiPiece(color: IslandPlayful.confetti.randomElement() ?? IslandTheme.sun, shape: Int.random(in: 0...3),
                             burst: CGSize(width: cos(angle) * distance, height: sin(angle) * distance * 0.8),
                             fall: CGFloat.random(in: 90...190), spin: Double.random(in: -540...540),
                             flip: Double.random(in: 180...720), size: CGFloat.random(in: 7...12))
    }
}

/// A short burst of paper confetti and leaves each time `trigger` becomes a new value.
struct ConfettiBurst: View {
    let trigger: UUID?
    var spread: CGFloat = 170
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pieces: [ConfettiPiece] = []
    @State private var phase = 0
    @State private var burstID: UUID?
    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                pieceView(piece)
                    .rotation3DEffect(.degrees(phase > 0 ? piece.flip : 0), axis: (x: 1, y: 0.3, z: 0))
                    .rotationEffect(.degrees(phase > 0 ? piece.spin : 0))
                    .offset(x: phase > 0 ? piece.burst.width : 0,
                            y: phase == 0 ? 0 : piece.burst.height + (phase > 1 ? piece.fall : 0))
                    .opacity(phase > 1 ? 0 : 1)
                    .scaleEffect(phase == 0 ? 0.3 : 1)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onChange(of: trigger) { _, value in
            guard let value, !reduceMotion, IslandPlayful.enabled else { return }
            Task { await launch(value) }
        }
    }
    @ViewBuilder private func pieceView(_ piece: ConfettiPiece) -> some View {
        switch piece.shape {
        case 0: RoundedRectangle(cornerRadius: 2).fill(piece.color).frame(width: piece.size, height: piece.size * 1.5)
        case 1: Circle().fill(piece.color).frame(width: piece.size, height: piece.size)
        case 2: Capsule().fill(piece.color).frame(width: piece.size * 0.7, height: piece.size * 1.6)
        default: Image(systemName: "leaf.fill").font(.system(size: piece.size * 1.3)).foregroundStyle(piece.color)
        }
    }
    @MainActor private func launch(_ id: UUID) async {
        burstID = id
        var reset = Transaction(); reset.disablesAnimations = true
        withTransaction(reset) { phase = 0; pieces = (0..<32).map { _ in ConfettiPiece.random(spread: spread) } }
        do {
            try await Task.sleep(for: .milliseconds(16))
            guard burstID == id else { return }
            withAnimation(.timingCurve(0.12, 0.85, 0.3, 1, duration: 0.65)) { phase = 1 }
            try await Task.sleep(for: .milliseconds(520))
            guard burstID == id else { return }
            withAnimation(.easeIn(duration: 0.85)) { phase = 2 }
            try await Task.sleep(for: .milliseconds(900))
            guard burstID == id else { return }
            withTransaction(reset) { pieces = []; phase = 0 }
        } catch { return }
    }
}

// MARK: - Empty states

/// The companion with a mood, a title, a message and optional actions.
/// Tapping the companion makes it hop and wave.
struct IslandEmptyState<Actions: View>: View {
    let title: String
    let message: String?
    let mood: IslandMood
    let actions: Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var poke: UUID?
    @State private var shown = false
    init(title: String, message: String? = nil, mood: IslandMood = .sleepy, @ViewBuilder actions: () -> Actions) {
        self.title = title; self.message = message; self.mood = mood; self.actions = actions()
    }
    var body: some View {
        let still = shown || reduceMotion || !IslandPlayful.enabled
        VStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                MoonIslandMascot(mood: mood, reaction: poke).frame(width: 104, height: 104)
                    .overlay {
                        Rectangle().fill(Color.white.opacity(0.001))
                            .onTapGesture { poke = UUID(); FeedbackHaptics.tap() }
                            .accessibilityHidden(true)
                    }
                    .scaleEffect(still ? 1 : 0.6, anchor: .bottom)
                    .rotationEffect(.degrees(still ? 0 : -12))
            }
            Text(title).font(.title3.weight(.bold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            actions.padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 18).padding(.horizontal, 12)
        .opacity(still ? 1 : 0).offset(y: still ? 0 : 16)
        .accessibilityElement(children: .contain)
        .task {
            guard !shown else { return }
            guard !reduceMotion, IslandPlayful.enabled else { shown = true; return }
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { shown = true }
            do { try await Task.sleep(for: .milliseconds(380)) } catch { return }
            poke = UUID()
        }
    }
}
extension IslandEmptyState where Actions == EmptyView {
    init(title: String, message: String? = nil, mood: IslandMood = .sleepy) {
        self.init(title: title, message: message, mood: mood) { EmptyView() }
    }
}

// MARK: - Streak

/// Consecutive days with at least one entry, ending today (or yesterday, so an
/// unlogged morning doesn't reset it). Display only.
enum IslandStreak {
    static func days(in expenses: [Expense], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = Set(expenses.map { calendar.startOfDay(for: $0.date) })
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

/// A flame-and-count chip that bounces when the streak grows.
struct IslandStreakChip: View {
    let days: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bump = 0
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .foregroundStyle(days > 0 ? Color(red: 1, green: 0.55, blue: 0.20) : Color.secondary)
                .symbolEffect(.bounce, value: bump)
            Text(days > 0 ? tr("连续记账 \(days) 天", "\(days)-day streak", "Rentetan \(days) hari")
                          : tr("今天开始连续记账", "Start a streak today", "Mulakan rentetan hari ini"))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(value: Double(days)))
        }
        .font(.caption.weight(.bold)).foregroundStyle(.primary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(IslandTheme.sun.opacity(0.22), in: Capsule())
        .overlay(Capsule().strokeBorder(IslandTheme.line, lineWidth: 1.5))
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.35), value: days)
        .onChange(of: days) { old, new in
            guard new > old, !reduceMotion, IslandPlayful.enabled else { return }
            bump += 1; FeedbackHaptics.pop()
        }
        .accessibilityElement(children: .combine)
    }
}
