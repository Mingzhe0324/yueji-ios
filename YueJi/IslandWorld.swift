import SwiftUI
import UIKit

// MARK: - Progress

/// Recording progress that grows the Overview island. Display only: it rewards the habit
/// of recording (days with entries), never the amount spent.
struct IslandProgress: Equatable {
    var streak = 0
    var loggedDays = 0
    /// Logged-day thresholds where the island gains something new (levels 1...7).
    static let thresholds = [0, 3, 7, 14, 30, 60, 100]
    static let streakMilestones = [3, 7, 14, 30, 60, 100, 200, 365]
    var level: Int { (Self.thresholds.lastIndex(where: { loggedDays >= $0 }) ?? 0) + 1 }
    var levelFloor: Int { Self.thresholds[level - 1] }
    var nextThreshold: Int? { level < Self.thresholds.count ? Self.thresholds[level] : nil }

    static func make(expenses: [Expense], now: Date = Date(), calendar: Calendar = .current) -> IslandProgress {
        let days = Set(expenses.lazy.filter { $0.date <= now }.map { calendar.startOfDay(for: $0.date) })
        var cursor = calendar.startOfDay(for: now)
        // An unrecorded morning doesn't break yesterday's streak.
        if !days.contains(cursor) { cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor }
        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return IslandProgress(streak: streak, loggedDays: days.count)
    }
}

enum IslandLevels {
    static func name(_ level: Int) -> String {
        switch level {
        case 1: return tr("萌芽小岛", "Seedling Isle", "Pulau Benih")
        case 2: return tr("花开小岛", "Blossom Isle", "Pulau Bunga")
        case 3: return tr("椰林小岛", "Palm Isle", "Pulau Palma")
        case 4: return tr("温馨小屋", "Cottage Isle", "Pulau Pondok")
        case 5: return tr("扬帆海湾", "Sailing Cove", "Teluk Layar")
        case 6: return tr("彩虹海湾", "Rainbow Bay", "Teluk Pelangi")
        default: return tr("百鸟乐园", "Songbird Haven", "Syurga Burung")
        }
    }
    /// What appears at a level, for "… to grow …" and level-up messages.
    static func unlock(_ level: Int) -> String {
        switch level {
        case 2: return tr("一片小花", "flowers", "bunga-bunga")
        case 3: return tr("一棵椰子树", "a palm tree", "pokok kelapa")
        case 4: return tr("一间小屋", "a cosy cottage", "sebuah pondok")
        case 5: return tr("一艘小帆船", "a little sailboat", "sebuah perahu layar")
        case 6: return tr("一道彩虹", "a rainbow", "pelangi")
        default: return tr("一群小鸟", "songbirds", "burung-burung")
        }
    }
}

// MARK: - World card

/// Overview's living island: a time-of-day sky, drifting clouds, sea, swaying plants and the
/// companion. It grows with the days you record, celebrating each new level and streak
/// milestone once. Continuous motion runs only while visible and ambient motion is allowed.
struct IslandWorldCard: View {
    /// `nil` until the ledger's progress has been computed.
    let progress: IslandProgress?
    let mood: IslandMood
    let line: String
    /// Each new value makes the companion celebrate (for example, after a save).
    var cheer: UUID? = nil
    var isPreview = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage("playfulAnimations") private var playful = true
    @AppStorage("ambientAnimations") private var ambient = true
    @AppStorage("islandLevelSeen") private var levelSeen = 0
    @AppStorage("islandStreakMilestoneSeen") private var streakSeen = 0
    @State private var visible = false
    @State private var alive = false
    @State private var spoken: String?
    @State private var spokenID = UUID()
    @State private var confetti: UUID?
    @State private var companionCheer: UUID?
    private var shown: IslandProgress { progress ?? IslandProgress() }
    private var shownLine: String { spoken ?? line }
    private var ambientOn: Bool {
        visible && phase == .active && IslandAmbient.allowed(playful: playful, ambient: ambient, reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IslandScene(level: shown.level, mood: mood, alive: alive, cheer: companionCheer, onSpeak: speak)
                .frame(height: 176)
                .accessibilityHidden(true)
                .overlay(alignment: .top) { ConfettiBurst(trigger: confetti, spread: 150).padding(.top, 70) }
            info
        }
        .background(IslandTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(IslandTheme.line, lineWidth: 2))
        .background { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(IslandTheme.ledge).offset(y: 5) }
        .padding(.bottom, 5)
        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .onChange(of: ambientOn, initial: true) { _, on in setAlive(on) }
        .onChange(of: cheer) { _, value in if value != nil { companionCheer = value } }
        .task(id: progress) { await checkMilestones() }
        .task(id: spokenID) {
            guard spoken != nil else { return }
            do { try await Task.sleep(for: .seconds(3.5)) } catch { return }
            spoken = nil
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(tr("第 \(shown.level) 级", "Lv \(shown.level)", "Tahap \(shown.level)"))
                    .font(.caption.weight(.heavy)).foregroundStyle(Color(red: 0.12, green: 0.22, blue: 0.18))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(IslandTheme.sun, in: Capsule())
                Text(IslandLevels.name(shown.level)).font(.headline).foregroundStyle(IslandTheme.accent)
                Spacer(minLength: 0)
            }
            Text(shownLine)
                .font(.subheadline.weight(spoken == nil ? .regular : .semibold))
                .foregroundStyle(spoken == nil ? Color.secondary : IslandTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
                .id(shownLine)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
            SpendingMeter(value: meter.value, total: meter.total, color: IslandTheme.sun)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Text(nextText).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    IslandStreakChip(days: shown.streak)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(nextText).font(.caption).foregroundStyle(.secondary)
                    IslandStreakChip(days: shown.streak)
                }
            }
        }
        .padding(16)
        .animation(reduceMotion ? nil : YueJiMotion.content, value: shownLine)
    }

    /// Days recorded within the current level, out of the days it takes; full when complete.
    private var meter: (value: Int, total: Int) {
        guard let next = shown.nextThreshold else { return (1, 1) }
        return (shown.loggedDays - shown.levelFloor, max(1, next - shown.levelFloor))
    }

    private var nextText: String {
        guard let next = shown.nextThreshold else {
            return tr("小岛已经完全长大啦！", "Your island is fully grown!", "Pulau anda sudah lengkap!")
        }
        let remaining = max(1, next - shown.loggedDays)
        let item = IslandLevels.unlock(shown.level + 1)
        return tr("再记 \(remaining) 天，就会长出\(item)",
                  remaining == 1 ? "1 more day of recording to grow \(item)" : "\(remaining) more days of recording to grow \(item)",
                  "\(remaining) hari lagi merekod untuk menumbuhkan \(item)")
    }

    private func setAlive(_ on: Bool) {
        if on { alive = true; return }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { alive = false }
    }

    private func speak(_ text: String) {
        spoken = text
        spokenID = UUID()
    }

    private func checkMilestones() async {
        guard let progress, !isPreview else { return }
        let reachedMilestone = IslandProgress.streakMilestones.last(where: { $0 <= progress.streak }) ?? 0
        // First sighting (including the first launch after this update): remember quietly.
        if levelSeen == 0 {
            levelSeen = progress.level
            streakSeen = reachedMilestone
            return
        }
        // A broken streak can celebrate its milestones again later.
        if reachedMilestone < streakSeen { streakSeen = reachedMilestone }
        // Each milestone is marked seen only once its celebration has actually played, so
        // leaving the screen mid-way shows it next time instead of losing it.
        if progress.level > levelSeen {
            let item = IslandLevels.unlock(progress.level)
            if await celebrate(tr("小岛长大了！新添了\(item)。", "Your island grew! Say hello to \(item).", "Pulau anda berkembang! Kini ada \(item).")) {
                levelSeen = progress.level
            }
        } else if reachedMilestone > streakSeen {
            if await celebrate(tr("连续记账 \(reachedMilestone) 天！好习惯正在长大。",
                                  "\(reachedMilestone)-day streak! A lovely habit is growing.",
                                  "Rentetan \(reachedMilestone) hari! Tabiat baik sedang berkembang.")) {
                streakSeen = reachedMilestone
            }
        }
    }

    /// Returns false if the screen went away before the celebration could play.
    private func celebrate(_ message: String) async -> Bool {
        // Let the screen settle before the party.
        do { try await Task.sleep(for: .milliseconds(450)) } catch { return false }
        speak(message)
        companionCheer = UUID()
        if playful && !reduceMotion { confetti = UUID() }
        FeedbackHaptics.success()
        FeedbackSounds.shared.play(.goal)
        if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: message) }
        return true
    }
}

// MARK: - Scene

private struct SkyPalette {
    let top: Color
    let bottom: Color
    let night: Bool
    static func now(_ date: Date = Date()) -> SkyPalette {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<8:
            return SkyPalette(top: Color(red: 1.0, green: 0.78, blue: 0.64), bottom: Color(red: 1.0, green: 0.93, blue: 0.80), night: false)
        case 8..<17:
            return SkyPalette(top: Color(red: 0.55, green: 0.82, blue: 0.98), bottom: Color(red: 0.84, green: 0.95, blue: 0.93), night: false)
        case 17..<19:
            return SkyPalette(top: Color(red: 0.98, green: 0.60, blue: 0.47), bottom: Color(red: 1.0, green: 0.84, blue: 0.64), night: false)
        default:
            return SkyPalette(top: Color(red: 0.07, green: 0.12, blue: 0.28), bottom: Color(red: 0.16, green: 0.31, blue: 0.42), night: true)
        }
    }
}

/// The illustrated island. Decorative for VoiceOver; the companion takes touches.
/// Every continuous motion is keyed to `alive` and stops when it turns false.
struct IslandScene: View {
    let level: Int
    let mood: IslandMood
    let alive: Bool
    var cheer: UUID? = nil
    var onSpeak: ((String) -> Void)? = nil
    private static let grass = Color(red: 0.30, green: 0.66, blue: 0.40)
    private static let lightGrass = Color(red: 0.48, green: 0.86, blue: 0.69)
    private static let wood = Color(red: 0.55, green: 0.36, blue: 0.20)
    private static let rainbowColors: [Color] = [
        Color(red: 0.95, green: 0.42, blue: 0.42), Color(red: 1.0, green: 0.66, blue: 0.30),
        Color(red: 1.0, green: 0.86, blue: 0.36), Color(red: 0.46, green: 0.80, blue: 0.52),
        Color(red: 0.42, green: 0.66, blue: 0.95)
    ]

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let sky = SkyPalette.now()
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [sky.top, sky.bottom], startPoint: .top, endPoint: .bottom)
                celestial(night: sky.night, w: w)
                if level >= 6 { rainbow.position(x: w * 0.5, y: h - 26) }
                clouds(w: w, night: sky.night)
                if level >= 7 { birds.position(x: w * 0.30, y: 42) }
                sea(w: w, h: h, back: true)
                island(w: w, h: h)
                sea(w: w, h: h, back: false)
            }
            .frame(width: w, height: h)
        }
        .clipped()
    }

    // MARK: Sky

    @ViewBuilder private func celestial(night: Bool, w: CGFloat) -> some View {
        if night {
            ZStack {
                Image(systemName: "moon.fill").font(.system(size: 26)).foregroundStyle(Color(red: 1, green: 0.92, blue: 0.62))
                    .position(x: w * 0.84, y: 32)
                ForEach(0..<5, id: \.self) { i in
                    let spot = Self.starSpots[i]
                    Image(systemName: "sparkle").font(.system(size: spot.size))
                        .foregroundStyle(.white.opacity(0.9))
                        .scaleEffect(alive && i.isMultiple(of: 2) ? 0.55 : 1)
                        .animation(alive ? .easeInOut(duration: 1.6 + Double(i) * 0.3).repeatForever(autoreverses: true) : nil, value: alive)
                        .position(x: w * spot.x, y: spot.y)
                }
            }
        } else {
            ZStack {
                Circle().fill(IslandTheme.sun.opacity(0.35)).frame(width: 58, height: 58)
                    .scaleEffect(alive ? 1.12 : 1)
                    .animation(alive ? .easeInOut(duration: 3).repeatForever(autoreverses: true) : nil, value: alive)
                Circle().fill(IslandTheme.sun).frame(width: 34, height: 34)
            }.position(x: w * 0.84, y: 34)
        }
    }

    private static let starSpots: [(x: CGFloat, y: CGFloat, size: CGFloat)] = [
        (0.12, 22, 10), (0.30, 46, 7), (0.52, 18, 9), (0.66, 52, 6), (0.08, 70, 7)
    ]

    private func clouds(w: CGFloat, night: Bool) -> some View {
        ZStack {
            cloud(64).position(x: w * 0.18, y: 30)
                .offset(x: alive ? 26 : 0)
                .animation(alive ? .easeInOut(duration: 11).repeatForever(autoreverses: true) : nil, value: alive)
            cloud(48).position(x: w * 0.56, y: 20)
                .offset(x: alive ? -24 : 0)
                .animation(alive ? .easeInOut(duration: 14).repeatForever(autoreverses: true) : nil, value: alive)
            cloud(40).position(x: w * 0.40, y: 58)
                .offset(x: alive ? 18 : 0)
                .animation(alive ? .easeInOut(duration: 9).repeatForever(autoreverses: true) : nil, value: alive)
        }.opacity(night ? 0.3 : 0.95)
    }

    private func cloud(_ width: CGFloat) -> some View {
        ZStack {
            Capsule().frame(width: width, height: width * 0.36).offset(y: width * 0.08)
            Circle().frame(width: width * 0.46, height: width * 0.46).offset(x: -width * 0.14, y: -width * 0.04)
            Circle().frame(width: width * 0.56, height: width * 0.56).offset(x: width * 0.10, y: -width * 0.08)
        }
        .foregroundStyle(.white)
        .frame(width: width, height: width * 0.6)
    }

    private var rainbow: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                Circle().trim(from: 0.5, to: 1)
                    .stroke(Self.rainbowColors[i], style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 220 - CGFloat(i) * 12, height: 220 - CGFloat(i) * 12)
            }
        }.opacity(0.7)
    }

    private var birds: some View {
        HStack(alignment: .top, spacing: 10) {
            bird.offset(y: alive ? -3 : 0)
            bird.scaleEffect(0.8).offset(y: alive ? 2 : -2)
        }
        .animation(alive ? .easeInOut(duration: 1.8).repeatForever(autoreverses: true) : nil, value: alive)
    }

    private var bird: some View {
        BirdShape().stroke(Color(red: 0.20, green: 0.24, blue: 0.30), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 8)
            .scaleEffect(x: 1, y: alive ? 0.45 : 1)
            .animation(alive ? .easeInOut(duration: 0.35).repeatForever(autoreverses: true) : nil, value: alive)
    }

    // MARK: Sea and island

    /// A seamless wave: it's one period wider than the scene and slides by exactly one period.
    private func sea(w: CGFloat, h: CGFloat, back: Bool) -> some View {
        let period: CGFloat = back ? 70 : 56
        let height: CGFloat = back ? 46 : 30
        let shift: CGFloat = back ? (alive ? 0 : period) : (alive ? period : 0)
        return SeaWave(period: period, amplitude: back ? 4 : 5)
            .fill(back ? Color(red: 0.40, green: 0.74, blue: 0.86) : Color(red: 0.24, green: 0.58, blue: 0.76))
            .frame(width: w + period, height: height)
            .offset(x: shift)
            .animation(alive ? .linear(duration: back ? 7 : 4.5).repeatForever(autoreverses: false) : nil, value: alive)
            .position(x: (w - period) / 2, y: h - height / 2)
    }

    private func island(w: CGFloat, h: CGFloat) -> some View {
        let top = h - 58 // The grass line.
        let cx = w / 2
        return ZStack {
            Ellipse().fill(Color(red: 0.90, green: 0.78, blue: 0.56)).frame(width: 204, height: 52)
                .position(x: cx, y: h - 34)
            Ellipse().fill(IslandTheme.accent).frame(width: 180, height: 32).position(x: cx, y: h - 48)
            Ellipse().fill(Self.lightGrass).frame(width: 152, height: 18).position(x: cx, y: h - 52)
            // Decorations sit to the sides so the companion stays clear.
            if level >= 3 {
                sway(palm, duration: 2.6, degrees: 3).position(x: cx - 72, y: top - 30)
            }
            if level >= 4 {
                cottage.position(x: cx + 76, y: top - 12)
            }
            if level >= 2 {
                sway(flower(Color(red: 0.96, green: 0.52, blue: 0.62)), duration: 2.0, degrees: 7).position(x: cx - 46, y: top + 2)
                sway(flower(Color(red: 0.62, green: 0.56, blue: 0.96)), duration: 2.3, degrees: 7).position(x: cx + 44, y: top + 4)
            } else {
                sway(sprout, duration: 2.2, degrees: 8).position(x: cx - 46, y: top + 2)
            }
            if level >= 5 {
                sailboat
                    .rotationEffect(.degrees(alive ? 4 : -3), anchor: .bottom)
                    .offset(y: alive ? -2 : 1)
                    .animation(alive ? .easeInOut(duration: 2.1).repeatForever(autoreverses: true) : nil, value: alive)
                    .position(x: max(28, cx - 138), y: h - 40)
            }
            InteractiveCompanion(mood: mood, size: 74, cheer: cheer, greeting: .wave, greetKey: "overview", onSpeak: onSpeak)
                .position(x: cx, y: top - 26)
        }
    }

    private func sway<Content: View>(_ content: Content, duration: Double, degrees: Double) -> some View {
        content
            .rotationEffect(.degrees(alive ? degrees : -degrees * 0.4), anchor: .bottom)
            .animation(alive ? .easeInOut(duration: duration).repeatForever(autoreverses: true) : nil, value: alive)
    }

    private var sprout: some View {
        ZStack {
            Capsule().fill(Self.grass).frame(width: 3, height: 12).offset(y: 5)
            Ellipse().fill(Self.grass).frame(width: 11, height: 6).rotationEffect(.degrees(-30)).offset(x: -5, y: -2)
            Ellipse().fill(Self.lightGrass).frame(width: 11, height: 6).rotationEffect(.degrees(30)).offset(x: 5, y: -3)
        }.frame(width: 24, height: 22)
    }

    private func flower(_ color: Color) -> some View {
        ZStack {
            Capsule().fill(Self.grass).frame(width: 3, height: 14).offset(y: 8)
            ForEach(0..<5, id: \.self) { i in
                Circle().fill(color).frame(width: 7, height: 7)
                    .offset(y: -4)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            Circle().fill(IslandTheme.sun).frame(width: 5, height: 5)
        }.frame(width: 20, height: 30)
    }

    private var palm: some View {
        ZStack {
            PalmTrunk().stroke(Self.wood, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: 30, height: 56)
                .position(x: 35, y: 56)
            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(i.isMultiple(of: 2) ? Self.grass : IslandTheme.accent)
                        .frame(width: 34, height: 10)
                        .offset(x: 15)
                        .rotationEffect(.degrees(Self.palmAngles[i]))
                }
                Circle().fill(Self.wood).frame(width: 7, height: 7).offset(x: -4, y: 5)
                Circle().fill(Self.wood).frame(width: 7, height: 7).offset(x: 4, y: 6)
            }.position(x: 43, y: 28)
        }.frame(width: 70, height: 84)
    }

    private static let palmAngles: [Double] = [20, -30, -90, -150, 160]

    private var cottage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color(red: 1, green: 0.96, blue: 0.88))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Self.wood.opacity(0.6), lineWidth: 1.5))
                .frame(width: 34, height: 24).offset(y: 8)
            TriangleShape().fill(Color(red: 0.88, green: 0.40, blue: 0.36)).frame(width: 46, height: 22).offset(y: -11)
            RoundedRectangle(cornerRadius: 2).fill(Self.wood).frame(width: 8, height: 13).offset(x: -6, y: 13)
            RoundedRectangle(cornerRadius: 1.5).fill(Color(red: 0.62, green: 0.84, blue: 0.98)).frame(width: 8, height: 7).offset(x: 8, y: 6)
        }.frame(width: 48, height: 48)
    }

    private var sailboat: some View {
        ZStack {
            Capsule().fill(Self.wood).frame(width: 2.5, height: 30).offset(y: -6)
            TriangleShape().fill(.white).frame(width: 18, height: 24).offset(x: 9, y: -10)
            TriangleShape().fill(Color(red: 0.95, green: 0.42, blue: 0.42)).frame(width: 9, height: 6).rotationEffect(.degrees(90)).offset(x: 4, y: -22)
            BoatHull().fill(Color(red: 0.86, green: 0.46, blue: 0.30)).frame(width: 38, height: 10).offset(y: 12)
        }.frame(width: 42, height: 50)
    }
}

// MARK: - Shapes

/// A sine wave filled downward, with crests repeating every `period` points.
struct SeaWave: Shape {
    var period: CGFloat
    var amplitude: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.minY + amplitude
        p.move(to: CGPoint(x: rect.minX, y: mid))
        var x: CGFloat = 0
        while x <= rect.width {
            p.addLine(to: CGPoint(x: rect.minX + x, y: mid + sin(x / period * 2 * .pi) * amplitude))
            x += 3
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct PalmTrunk: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX - 4, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.midX + 8, y: rect.minY), control: CGPoint(x: rect.midX - 10, y: rect.midY))
        return p
    }
}

private struct BoatHull: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct BirdShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.midY), control: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.minX + rect.width * 0.75, y: rect.minY))
        return p
    }
}
