import SwiftUI

/// The opening, "the moon of the month", about 1.1 s to the reveal. 月记 is a moon (月)
/// that is also a month, and a record (记) kept day by day:
///
/// 1. Dusk. The page lights up, a few gold stars come out, and this month's days appear
///    around the centre one by one, clockwise from the 1st, with a gold thread running from
///    the 1st to today. Days gone are brighter than days to come; today is a gold bead.
/// 2. Moonrise. The glass moon of the app icon rises into the middle of the days.
/// 3. Waxing. The gold crescent grows from a new moon into the icon's crescent, and the
///    icon's three entries are written across the glass, one stroke after another.
/// 4. Named. The name settles in letter by letter, its line beneath, and today's bead
///    sends out one ripple.
///
/// Once the ledger has loaded, MainView reveals the app through the moon: it opens like
/// an iris past the screen's corners behind a fading gold rim (`AnyTransition.openingIris`).
/// Before iOS 26, and with Reduce Transparency, the moon is solid blue rather than glass;
/// with Animations off or Reduce Motion the finished picture shows at once and fades.
struct OpeningAnimationView: View {
    @Environment(\.locale) private var uiLocale
    var sound = true
    /// Whether the ledger has loaded. The reveal waits for it, so it never opens onto a blank screen.
    var ready = true
    var onFinished: () -> Void
    @Environment(\.scenePhase) private var phase
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("playfulAnimations") private var playful = true
    @State private var playedSound = false
    @State private var stage = OpeningStage.start
    @State private var twinkling = false
    @State private var finished = false
    /// Mirrors `ready` so the running sequence sees updates while it waits.
    @State private var ledgerReady = false
    /// True from the moment the reveal starts (or the opening ends).
    @State private var revealed = false
    /// This month, read once: the dial must not change under the animation at midnight.
    @State private var month = OpeningMonth()
    private var animates: Bool { playful && !reduceMotion }
    /// The step to draw: without animation, the finished picture straight away.
    private var shown: OpeningStage { animates ? stage : .named }

    /// The moon's diameter, and the radius of the ring of days around it.
    private static let moonSize: CGFloat = 116
    private static let ringRadius: CGFloat = 96
    /// The icon's three entries in units of the moon's radius: rows from the centre,
    /// lengths, thickness and their shared leading edge (from `generate_icon.py`).
    private static let entryRows: [CGFloat] = [-0.403, -0.097, 0.208]
    private static let entryLengths: [CGFloat] = [0.944, 0.75, 0.556]
    private static let entryThickness: CGFloat = 0.144
    private static let entryLeading: CGFloat = -0.33

    var body: some View {
        let _ = uiLocale.identifier
        ZStack {
            Color("LaunchBackground")
            // The tabs' lit page, so the opening hands over to the Overview seamlessly.
            AmbientGlowBackdrop()
                .opacity(shown >= .dusk ? 1 : 0)
                .animation(.smooth(duration: 0.5), value: shown)
            moonlight
            stars
            ZStack {
                dial
                moon
                moonDetail
                VStack(spacing: 6) {
                    wordmark
                    tagline
                }
                .offset(y: Self.ringRadius + 58)
            }
        }
        .ignoresSafeArea()
        // Skipping is handled by MainView: this layer never takes touches.
        .onChange(of: ready, initial: true) { _, value in ledgerReady = value }
        .task {
            // Finishing the optional opening must not depend on scene callbacks.
            // Give the initial frame time to appear without blocking the UI.
            do {
                try await Task.sleep(for: .milliseconds(30))
                guard animates else {
                    try await Task.sleep(for: .milliseconds(100))
                    finish(); return
                }
                // Each layer animates its own part of every step (see the views below).
                stage = .dusk
                try await Task.sleep(for: .milliseconds(170))
                stage = .moonrise
                try await Task.sleep(for: .milliseconds(290))
                stage = .waxing
                try await Task.sleep(for: .milliseconds(200))
                // On its own beat: a step changing at the same moment would replace the
                // repeating twinkle with that step's one-off animation.
                twinkling = true
                try await Task.sleep(for: .milliseconds(130))
                stage = .named
                // The crescent completes about now: one soft tap to go with it.
                if sound { FeedbackHaptics.pop() }
                try await Task.sleep(for: .milliseconds(300))
                // Hold while the ledger loads: the reveal only opens onto real content.
                while !ledgerReady { try await Task.sleep(for: .milliseconds(50)) }
                finish()
            } catch { return }
        }
        .task(id: phase) {
            // Sound still waits for foreground activation; screen readiness does not.
            guard phase == .active, sound, !playedSound else { return }
            FeedbackSounds.shared.play(.launch)
            playedSound = true
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(tr("月记 YueJi", "YueJi", "YueJi"))
        .accessibilityAction { finish() }
        // Once the app is being revealed, leave the accessibility tree immediately. Otherwise
        // the full-screen element lingers during the reveal and makes the newly mounted
        // toolbar (Add Entry) look covered to accessibility hit-testing and UI tests.
        .accessibilityHidden(revealed)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        revealed = true
        onFinished()
    }

    // MARK: Sky

    /// A soft blue glow behind the moon, like moonlight on haze.
    private var moonlight: some View {
        Circle()
            .fill(RadialGradient(colors: [IslandTheme.accent.opacity(scheme == .dark ? 0.32 : 0.18), IslandTheme.accent.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: 170))
            .frame(width: 340, height: 340)
            .scaleEffect(shown >= .moonrise ? 1 : 0.6)
            .opacity(shown >= .moonrise ? 1 : 0)
            .animation(.smooth(duration: 0.8), value: shown)
            .accessibilityHidden(true)
    }

    private var stars: some View {
        ZStack {
            ForEach(OpeningStar.all) { star in
                OpeningSparkle()
                    .fill(OpeningPalette.star(scheme))
                    .frame(width: star.size, height: star.size)
                    .scaleEffect(shown >= .dusk ? 1 : 0.2)
                    .opacity(shown >= .dusk ? (twinkling ? star.glow * 0.35 : star.glow) : 0)
                    .offset(x: star.x, y: star.y)
                    .animation(.smooth(duration: 0.5).delay(star.delay), value: shown)
                    // A slow, uneven twinkle once the name is in.
                    .animation(.easeInOut(duration: star.twinkle).repeatForever(autoreverses: true).delay(star.delay), value: twinkling)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: The days of the month

    /// The month around the moon: one bead per day, clockwise from the 1st at the top, a
    /// gold thread from the 1st to today, and today's bead in gold.
    private var dial: some View {
        let sweep = 0.42 / Double(month.days)
        return ZStack {
            Circle()
                .trim(from: 0, to: shown >= .dusk ? month.thread : 0)
                .stroke(OpeningPalette.gold, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: Self.ringRadius * 2, height: Self.ringRadius * 2)
                .rotationEffect(.degrees(-90))
                .opacity(0.9)
                .animation(.easeInOut(duration: 0.75).delay(0.08), value: shown)
            ForEach(Array(1...month.days), id: \.self) { day in
                let isToday = day == month.today
                Group {
                    if isToday {
                        Circle().fill(OpeningPalette.gold)
                            .frame(width: 8, height: 8)
                            .shadow(color: OpeningPalette.glow.opacity(0.9), radius: 5)
                    } else {
                        Circle().fill(Color.primary.opacity(day < month.today ? 0.42 : 0.15))
                            .frame(width: 4.5, height: 4.5)
                    }
                }
                .scaleEffect(shown >= .dusk ? 1 : 0.1)
                .opacity(shown >= .dusk ? 1 : 0)
                .animation(.spring(duration: 0.38, bounce: 0.35).delay(Double(day - 1) * sweep), value: shown)
                .offset(y: -Self.ringRadius)
                .rotationEffect(.degrees(month.angle(of: day)))
            }
            // Today's ripple as the name arrives.
            Circle()
                .stroke(OpeningPalette.gold, lineWidth: 1)
                .frame(width: 10, height: 10)
                .scaleEffect(shown >= .named ? 3.2 : 1)
                .opacity(shown >= .named ? 0 : (shown >= .waxing ? 0.9 : 0))
                .animation(shown >= .named ? .easeOut(duration: 0.9) : .smooth(duration: 0.3), value: shown)
                .offset(y: -Self.ringRadius)
                .rotationEffect(.degrees(month.angle(of: month.today)))
        }
        .frame(width: Self.ringRadius * 2 + 16, height: Self.ringRadius * 2 + 16)
        .accessibilityHidden(true)
    }

    // MARK: The moon

    /// The icon's glass moon, rising into place. One glass circle on iOS 26 and later, so it
    /// takes the system's own Liquid Glass; a solid blue disc otherwise.
    @ViewBuilder private var moonDisc: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            Color.clear.frame(width: Self.moonSize, height: Self.moonSize)
                .glassEffect(.regular.tint(IslandTheme.accent), in: Circle())
        } else {
            Circle().fill(IslandTheme.accent.gradient).frame(width: Self.moonSize, height: Self.moonSize)
        }
    }

    private var moon: some View {
        moonDisc
            .scaleEffect(shown >= .moonrise ? 1 : 0.55)
            .offset(y: shown >= .moonrise ? 0 : 34)
            .opacity(shown >= .moonrise ? 1 : 0)
            .animation(.spring(duration: 0.6, bounce: 0.22), value: shown)
            .accessibilityHidden(true)
    }

    /// The icon's moon on the glass: the gold crescent (月) waxing from a new moon, and the
    /// three white entries (记) written left to right just clear of it, as in the icon.
    private var moonDetail: some View {
        let r = Self.moonSize / 2
        let rounding = r * 0.033
        let thickness = r * Self.entryThickness
        let waxed = shown >= .waxing
        return ZStack {
            ForEach(0..<3, id: \.self) { index in
                let length = r * Self.entryLengths[index]
                let x = r + r * Self.entryLeading
                let y = r + r * Self.entryRows[index]
                Path { path in
                    // Round caps add half the thickness at each end, so the stroke spans the
                    // icon's capsule exactly.
                    path.move(to: CGPoint(x: x + thickness / 2, y: y))
                    path.addLine(to: CGPoint(x: x + length - thickness / 2, y: y))
                }
                .trim(from: 0, to: waxed ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                .shadow(color: OpeningPalette.ink.opacity(0.25), radius: 2, y: 1)
                .opacity(waxed ? 1 : 0)
                .animation(.easeOut(duration: 0.26).delay(0.2 + Double(index) * 0.09), value: shown)
            }
            MoonCrescent(phase: waxed ? 1 : 0, rounding: rounding)
                .fill(OpeningPalette.gold)
                .overlay {
                    MoonCrescent(phase: waxed ? 1 : 0, rounding: rounding)
                        .stroke(OpeningPalette.gold, style: StrokeStyle(lineWidth: rounding * 2, lineJoin: .round))
                }
                .shadow(color: OpeningPalette.ink.opacity(0.35), radius: r * 0.05, x: r * 0.028, y: r * 0.05)
                .animation(.easeInOut(duration: 0.55), value: shown)
        }
        .frame(width: Self.moonSize, height: Self.moonSize)
        .accessibilityHidden(true)
    }

    // MARK: The name

    /// The name, its letters settling in one after another out of a soft blur.
    private var wordmark: some View {
        let letters = Array(tr("月记", "YueJi", "YueJi")).map(String.init)
        let named = shown >= .named
        return HStack(spacing: AppLanguage.code == "zh" ? 4 : 0) {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                Text(letter)
                    .blur(radius: named ? 0 : 8)
                    .offset(y: named ? 0 : 10)
                    .opacity(named ? 1 : 0)
                    .animation(.smooth(duration: 0.45).delay(Double(index) * 0.06), value: shown)
            }
        }
        .font(.system(size: 34, weight: .bold))
        .foregroundStyle(.primary)
    }

    /// The app's line, as on its Settings card.
    private var tagline: some View {
        Text(tr("让每一笔，都清楚。", "Clarity in every entry.", "Jelas dalam setiap rekod."))
            .font(.subheadline)
            .tracking(0.4)
            .foregroundStyle(.secondary)
            .opacity(shown >= .named ? 1 : 0)
            .offset(y: shown >= .named ? 0 : 6)
            .animation(.smooth(duration: 0.5).delay(0.22), value: shown)
    }
}

/// The opening's steps, in order.
private enum OpeningStage: Int, Comparable {
    /// The first frame: only the background, as the system launch screen.
    case start
    /// The page lights, stars come out and the month's days appear around the centre.
    case dusk
    /// The glass moon rises into the middle of the days.
    case moonrise
    /// The crescent waxes and the three entries are written.
    case waxing
    /// The name and its line settle; today's bead ripples.
    case named
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// This month on the opening's dial.
private struct OpeningMonth {
    let days: Int
    /// Today's day of the month, from 1.
    let today: Int
    init(date: Date = Date(), calendar: Calendar = .current) {
        let count = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        days = max(count, 1)
        today = min(max(calendar.component(.day, from: date), 1), days)
    }
    /// A day's place on the dial: degrees clockwise from twelve o'clock.
    func angle(of day: Int) -> Double { Double(day - 1) / Double(days) * 360 }
    /// How far round the thread runs: from the 1st to today.
    var thread: CGFloat { CGFloat(today - 1) / CGFloat(days) }
}

/// One star of the opening's sky, placed from the centre.
private struct OpeningStar: Identifiable {
    let id: Int
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    /// Resting brightness.
    let glow: Double
    let delay: Double
    /// Seconds for one twinkle.
    let twinkle: Double
    static let all = [
        OpeningStar(id: 0, x: -134, y: -232, size: 10, glow: 0.9, delay: 0.02, twinkle: 1.6),
        OpeningStar(id: 1, x: 122, y: -190, size: 7, glow: 0.7, delay: 0.12, twinkle: 1.2),
        OpeningStar(id: 2, x: -58, y: -300, size: 5, glow: 0.55, delay: 0.2, twinkle: 1.9),
        OpeningStar(id: 3, x: 156, y: -36, size: 6, glow: 0.6, delay: 0.08, twinkle: 1.4),
        OpeningStar(id: 4, x: -160, y: 40, size: 6, glow: 0.6, delay: 0.16, twinkle: 1.7),
        OpeningStar(id: 5, x: 110, y: 250, size: 8, glow: 0.75, delay: 0.24, twinkle: 1.3),
        OpeningStar(id: 6, x: -118, y: 284, size: 5, glow: 0.5, delay: 0.3, twinkle: 2.0),
    ]
}

/// A four-pointed sparkle with softly curved sides.
private struct OpeningSparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * 0.26
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y - w))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + w, y: c.y + w))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y + w))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - w, y: c.y - w))
        path.closeSubpath()
        return path
    }
}

/// The icon's lit crescent (月): the moon's disc minus a disc of 0.98 its radius, centred
/// 0.45 of its radius away up and to the right (38°), as `generate_icon.py` draws it. The
/// phase slides the cut from the centre (a new moon: nothing lit) out to that place, so the
/// crescent waxes. Inset by `rounding`, so a round-joined stroke twice that wide rounds the horns.
struct MoonCrescent: Shape {
    var phase: CGFloat = 1
    var rounding: CGFloat = 0
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let angle = 38 * Double.pi / 180
        let reach = r * 0.45 * min(max(phase, 0), 1)
        let disc = Self.circle(CGPoint(x: rect.midX, y: rect.midY), r - rounding)
        let cut = Self.circle(CGPoint(x: rect.midX + reach * CGFloat(cos(angle)),
                                      y: rect.midY - reach * CGFloat(sin(angle))), r * 0.98 + rounding)
        return disc.subtracting(cut)
    }
    private static func circle(_ centre: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }
}

/// The icon's colours, shared by the opening and its reveal.
private enum OpeningPalette {
    /// The icon's shadow colour.
    static let ink = Color(red: 6 / 255, green: 26 / 255, blue: 80 / 255)
    static let gold = MoonGold.gradient
    static let glow = MoonGold.glow
    /// Warm white stars at night, deeper gold ones on the light page.
    static func star(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1, green: 236 / 255, blue: 190 / 255) : Color(red: 226 / 255, green: 160 / 255, blue: 70 / 255)
    }
}

// MARK: - The moon as a loading indicator

/// The opening's moon in miniature while something loads: its gold crescent waxes and
/// wanes on a slow loop. Still, at the icon's crescent, with Reduce Motion or Animations off.
struct WaxingMoonIndicator: View {
    var size: CGFloat = 28
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var waxed = false
    var body: some View {
        let animates = !reduceMotion && ElegantMotion.enabled
        ZStack {
            Circle().fill(IslandTheme.accent.gradient)
            MoonCrescent(phase: animates ? (waxed ? 1 : 0.12) : 1, rounding: size * 0.016)
                .fill(OpeningPalette.gold)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard animates else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { waxed = true }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - The reveal

extension AnyTransition {
    /// The opening's exit: the app appears through the moon, which opens like an iris past
    /// the screen's corners behind a fading gold rim, as the opening drifts slightly closer.
    static var openingIris: AnyTransition {
        .modifier(active: OpeningIris(progress: 1), identity: OpeningIris(progress: 0))
            .animation(.easeInOut(duration: 0.62))
    }
}

/// A hole in the opening, centred on the moon, from closed (0) to past the corners (1).
private struct OpeningIris: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 + 0.08 * progress)
            .mask {
                OpeningIrisMask(progress: progress)
                    .fill(style: FillStyle(eoFill: true))
                    .ignoresSafeArea()
            }
            .overlay {
                GeometryReader { proxy in
                    let radius = OpeningIrisMask.reach(proxy.size) * CGFloat(progress)
                    Circle()
                        .stroke(OpeningPalette.gold, lineWidth: 2.5)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .ignoresSafeArea()
                // Nothing at either end; brightest halfway.
                .opacity(sin(progress * .pi) * 0.85)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

/// The whole screen and then some, less a circle at the centre: filled even-odd, it keeps
/// everything outside the circle.
private struct OpeningIrisMask: Shape {
    var progress: Double
    /// From the centre to just past the corners.
    static func reach(_ size: CGSize) -> CGFloat {
        (size.width * size.width + size.height * size.height).squareRoot() / 2 + 8
    }
    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -80, dy: -80))
        let radius = Self.reach(rect.size) * CGFloat(min(max(progress, 0), 1))
        if radius > 0 {
            path.addEllipse(in: CGRect(x: rect.midX - radius, y: rect.midY - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}
