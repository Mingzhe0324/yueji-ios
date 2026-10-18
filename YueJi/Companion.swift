import SwiftUI
import UIKit

// MARK: - Motion settings

/// Continuous "ambient" motion (breathing, idle blinks and glances, drifting scenery) is
/// separate from one-shot reactions. It runs only while a view is on screen and the app is
/// active, and is off with Reduce Motion, Low Power Mode, playful animations off or the
/// "ambientAnimations" setting. UI tests pass `-ambientAnimations NO`, because the test
/// runner waits for the app to be idle before every step.
enum IslandAmbient {
    static func allowed(playful: Bool, ambient: Bool, reduceMotion: Bool) -> Bool {
        playful && ambient && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

// MARK: - Companion model

/// The companion's base expression, chosen by the screen (budget state, empty states, banners).
enum IslandMood: String { case happy, excited, worried, sad, sleepy }

/// A one-shot cartoon action, played on top of the mood.
enum CompanionAction: CaseIterable {
    case wave, hop, giggle, spin, wink, surprised, dance, love, dizzy, stretch, celebrate, yawn, sigh
    /// Reactions a tap can trigger; the companion avoids repeating the previous one.
    static let tapReactions: [CompanionAction] = [.wave, .hop, .giggle, .spin, .wink, .surprised, .dance, .love]
}

/// Each new cue plays its action once. A newer cue interrupts the current one.
struct CompanionCue: Equatable {
    let id = UUID()
    let action: CompanionAction
}

private enum CompanionFace { case happy, excited, worried, sad, sleepy, wink, surprised, dizzy, love, giggle, yawn }

private enum CompanionParticle {
    case hearts, notes, stars
    var symbol: String {
        switch self {
        case .hearts: return "heart.fill"
        case .notes: return "music.note"
        case .stars: return "star.fill"
        }
    }
    var color: Color {
        switch self {
        case .hearts: return Color(red: 0.96, green: 0.38, blue: 0.50)
        case .notes: return IslandTheme.accent
        case .stars: return IslandTheme.sun
        }
    }
}

// MARK: - Mascot

/// The Moon Island companion, drawn from native shapes. Purely visual: interaction lives
/// in `InteractiveCompanion`, so decorative copies (banners, opening) never take touches.
struct MoonIslandMascot: View {
    var mood: IslandMood = .happy
    /// Each new value plays a short hop and wave.
    var reaction: UUID? = nil
    /// Each new cue plays its action once; a newer cue interrupts the current one.
    var cue: CompanionCue? = nil
    /// Where to look, each axis -1...1 (for example, toward a finger).
    var look: CGSize = .zero
    /// Idle life: breathing, blinking, glancing and dozing. Callers enable it only while
    /// the companion is visible and ambient motion is allowed.
    var lively = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("playfulAnimations") private var playful = true
    @State private var hop: CGFloat = 0
    @State private var squash: CGFloat = 1
    @State private var tilt = 0.0
    @State private var spin = 0.0
    @State private var shake: CGFloat = 0
    @State private var arms = 0.0
    @State private var waveArm = 0.0
    @State private var blink = false
    @State private var expression: CompanionFace?
    @State private var glance: CGSize = .zero
    @State private var breathe = false
    @State private var drift = false
    @State private var particle: CompanionParticle?
    @State private var burst = 0
    @State private var orbit = 0.0
    @State private var runID = UUID()
    @State private var busy = false
    private let ink = Color(red: 0.16, green: 0.23, blue: 0.22)
    private var motion: Bool { playful && !reduceMotion }
    private var face: CompanionFace {
        if let expression { return expression }
        switch mood {
        case .happy: return .happy
        case .excited: return .excited
        case .worried: return .worried
        case .sad: return .sad
        case .sleepy: return .sleepy
        }
    }
    private var gaze: CGSize {
        CGSize(width: max(-1, min(1, look.width + glance.width)), height: max(-1, min(1, look.height + glance.height)))
    }

    var body: some View {
        GeometryReader { geometry in
            let s = min(geometry.size.width, geometry.size.height)
            ZStack {
                Ellipse().fill(IslandTheme.accent.opacity(0.15))
                    .frame(width: s * 0.7, height: s * 0.12)
                    .scaleEffect(1 + hop * 1.4)
                    .offset(y: s * 0.39)
                figure(s)
                particles(s)
            }.frame(width: s, height: s)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true).allowsHitTesting(false)
        .animation(motion ? .spring(duration: 0.45, bounce: 0.35) : nil, value: mood)
        .task(id: reaction) { if reaction != nil { await perform(.hop) } }
        .task(id: cue?.id) { if let cue { await perform(cue.action) } }
        .task(id: "\(motion)-\(lively)-\(mood.rawValue)") { await live() }
    }

    // MARK: Drawing

    private func figure(_ s: CGFloat) -> some View {
        character(s)
            .scaleEffect(x: breathe ? 0.985 : 1, y: breathe ? 1.03 : 1, anchor: .bottom)
            .scaleEffect(x: 2 - squash, y: squash, anchor: .bottom)
            .rotationEffect(.degrees(tilt + spin + Double(gaze.width) * 4))
            .offset(x: shake * s, y: hop * s)
    }

    private func character(_ s: CGFloat) -> some View {
        let droop: Double = face == .sad ? 18 : 0
        let g = gaze
        return ZStack {
            arm(s).rotationEffect(.degrees(25 + droop + arms), anchor: .top).offset(x: -s * 0.23, y: s * 0.30)
            arm(s).rotationEffect(.degrees(-25 - droop - arms - waveArm), anchor: .top).offset(x: s * 0.23, y: s * 0.30)
            RoundedRectangle(cornerRadius: s * 0.34).fill(IslandTheme.sun)
                .frame(width: s * 0.76, height: s * 0.78)
                .overlay(RoundedRectangle(cornerRadius: s * 0.34).strokeBorder(Color.brown.opacity(0.25), lineWidth: 2))
            Ellipse().fill(.white.opacity(0.38)).frame(width: s * 0.28, height: s * 0.10)
                .rotationEffect(.degrees(-30)).offset(x: -s * 0.13, y: -s * 0.23)
            // Eye frames are wider than the pupils; this keeps the original eye spacing.
            HStack(spacing: s * 0.135) { eye(s, left: true); eye(s, left: false) }
                .offset(x: g.width * s * 0.035, y: g.height * s * 0.025)
            cheeks(s).offset(x: g.width * s * 0.02, y: s * 0.08)
            mouth(s).offset(x: g.width * s * 0.02, y: g.height * s * 0.01)
            Image(systemName: "leaf.fill").font(.system(size: s * 0.25)).foregroundStyle(IslandTheme.accent)
                .rotationEffect(.degrees(-20 + waveArm * 0.2 - Double(g.width) * 6), anchor: .bottomLeading)
                .offset(x: s * 0.16, y: -s * 0.38)
            extras(s)
        }
    }

    private func arm(_ s: CGFloat) -> some View {
        Capsule().fill(IslandTheme.accent).frame(width: s * 0.16, height: s * 0.24)
    }

    @ViewBuilder private func eye(_ s: CGFloat, left: Bool) -> some View {
        let w: CGFloat = s * 0.10
        switch face {
        case .excited, .giggle:
            if blink { openEye(s, left: left).frame(width: w, height: w) } else { arcEye(s, up: true).frame(width: w, height: w) }
        case .sleepy, .yawn:
            arcEye(s, up: false).frame(width: w, height: w)
        case .wink:
            if left { openEye(s, left: left).frame(width: w, height: w) } else { arcEye(s, up: true).frame(width: w, height: w) }
        case .surprised:
            bigEye(s).frame(width: w, height: w)
        case .dizzy:
            spiralEye(s).frame(width: w, height: w)
        case .love:
            Image(systemName: "heart.fill").font(.system(size: s * 0.10))
                .foregroundStyle(Color(red: 0.95, green: 0.35, blue: 0.45)).frame(width: w, height: w)
        case .happy, .worried, .sad:
            openEye(s, left: left).frame(width: w, height: w)
        }
    }

    private func openEye(_ s: CGFloat, left: Bool) -> some View {
        Capsule().fill(ink).frame(width: s * 0.055, height: s * 0.10)
            .scaleEffect(y: blink ? 0.15 : 1)
            .overlay(alignment: .top) {
                if face == .worried || face == .sad {
                    Capsule().fill(ink).frame(width: s * 0.10, height: max(2, s * 0.025))
                        .rotationEffect(.degrees(left ? -18 : 18)).offset(y: -s * 0.07)
                }
            }
    }

    /// "^" when `up`, closed "u" otherwise.
    private func arcEye(_ s: CGFloat, up: Bool) -> some View {
        let w: CGFloat = s * 0.10
        return Path { p in
            p.move(to: CGPoint(x: 0, y: up ? w * 0.75 : w * 0.35))
            p.addQuadCurve(to: CGPoint(x: w, y: up ? w * 0.75 : w * 0.35),
                           control: CGPoint(x: w / 2, y: up ? -w * 0.25 : w * 0.9))
        }.stroke(ink, style: StrokeStyle(lineWidth: max(2, s * 0.033), lineCap: .round))
    }

    private func bigEye(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(.white).overlay(Circle().strokeBorder(ink, lineWidth: max(1.5, s * 0.02)))
            Circle().fill(ink).frame(width: s * 0.045, height: s * 0.045)
        }
    }

    private func spiralEye(_ s: CGFloat) -> some View {
        let w: CGFloat = s * 0.10
        return Path { p in
            for i in 0...24 {
                let t = CGFloat(i) / 24
                let angle = t * .pi * 4
                let point = CGPoint(x: w / 2 + cos(angle) * w * 0.5 * t, y: w / 2 + sin(angle) * w * 0.5 * t)
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }.stroke(ink, lineWidth: max(1.5, s * 0.02))
    }

    private func cheeks(_ s: CGFloat) -> some View {
        let strong = face == .excited || face == .love || face == .giggle
        return HStack(spacing: s * 0.37) {
            Ellipse().fill(Color.pink.opacity(strong ? 0.6 : 0.35)).frame(width: s * 0.12, height: s * 0.055)
            Ellipse().fill(Color.pink.opacity(strong ? 0.6 : 0.35)).frame(width: s * 0.12, height: s * 0.055)
        }
    }

    @ViewBuilder private func mouth(_ s: CGFloat) -> some View {
        let line = StrokeStyle(lineWidth: max(2.5, s * 0.032), lineCap: .round)
        switch face {
        case .happy, .love:
            Path { p in
                p.move(to: CGPoint(x: s * 0.44, y: s * 0.59))
                p.addQuadCurve(to: CGPoint(x: s * 0.56, y: s * 0.59), control: CGPoint(x: s * 0.5, y: s * 0.69))
            }.stroke(ink, style: line).frame(width: s, height: s)
        case .excited, .giggle:
            openMouth(s, tall: 0.75).frame(width: s, height: s)
        case .yawn:
            ZStack {
                Ellipse().fill(ink).frame(width: s * 0.12, height: s * 0.15)
                Ellipse().fill(Color(red: 1, green: 0.45, blue: 0.48)).frame(width: s * 0.07, height: s * 0.04).offset(y: s * 0.04)
            }.position(x: s * 0.5, y: s * 0.64).frame(width: s, height: s)
        case .surprised:
            Ellipse().stroke(ink, lineWidth: max(2, s * 0.03)).frame(width: s * 0.08, height: s * 0.10)
                .position(x: s * 0.5, y: s * 0.63).frame(width: s, height: s)
        case .worried, .dizzy:
            Path { p in
                p.move(to: CGPoint(x: s * 0.42, y: s * 0.62))
                p.addCurve(to: CGPoint(x: s * 0.58, y: s * 0.62), control1: CGPoint(x: s * 0.47, y: s * 0.57), control2: CGPoint(x: s * 0.53, y: s * 0.67))
            }.stroke(ink, style: line).frame(width: s, height: s)
        case .sad:
            Path { p in
                p.move(to: CGPoint(x: s * 0.44, y: s * 0.64))
                p.addQuadCurve(to: CGPoint(x: s * 0.56, y: s * 0.64), control: CGPoint(x: s * 0.5, y: s * 0.56))
            }.stroke(ink, style: line).frame(width: s, height: s)
        case .sleepy:
            Ellipse().stroke(ink, lineWidth: max(2, s * 0.028)).frame(width: s * 0.055, height: s * 0.06)
                .position(x: s * 0.5, y: s * 0.62).frame(width: s, height: s)
        case .wink:
            // A lopsided, knowing smile.
            Path { p in
                p.move(to: CGPoint(x: s * 0.44, y: s * 0.60))
                p.addQuadCurve(to: CGPoint(x: s * 0.58, y: s * 0.57), control: CGPoint(x: s * 0.52, y: s * 0.68))
            }.stroke(ink, style: line).frame(width: s, height: s)
        }
    }

    private func openMouth(_ s: CGFloat, tall: CGFloat) -> some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: s * 0.41, y: s * 0.57))
                p.addQuadCurve(to: CGPoint(x: s * 0.59, y: s * 0.57), control: CGPoint(x: s * 0.5, y: s * tall))
                p.closeSubpath()
            }.fill(ink)
            Ellipse().fill(Color(red: 1, green: 0.45, blue: 0.48)).frame(width: s * 0.08, height: s * 0.035)
                .position(x: s * 0.5, y: s * 0.635)
        }
    }

    @ViewBuilder private func extras(_ s: CGFloat) -> some View {
        let fall: CGFloat = drift ? s * 0.10 : 0
        let rise: CGFloat = drift ? s * 0.08 : 0
        switch face {
        case .sad:
            Image(systemName: "drop.fill").font(.system(size: s * 0.10))
                .foregroundStyle(Color(red: 0.40, green: 0.72, blue: 1))
                .offset(x: -s * 0.15, y: s * 0.09 + fall).opacity(drift ? 0.15 : 1)
                .transition(.scale.combined(with: .opacity))
        case .sleepy, .yawn:
            ZStack {
                Text(verbatim: "z").font(.system(size: s * 0.13, weight: .heavy, design: .rounded)).offset(x: s * 0.36, y: -s * 0.22 - rise)
                Text(verbatim: "z").font(.system(size: s * 0.17, weight: .heavy, design: .rounded)).offset(x: s * 0.46, y: -s * 0.36 - rise)
            }.foregroundStyle(IslandTheme.accent).opacity(drift ? 0.4 : 1)
                .transition(.opacity)
        case .excited:
            ZStack {
                Image(systemName: "sparkle").font(.system(size: s * 0.14)).offset(x: -s * 0.44, y: -s * 0.30)
                Image(systemName: "sparkle").font(.system(size: s * 0.10)).offset(x: s * 0.46, y: -s * 0.06)
                Image(systemName: "sparkle").font(.system(size: s * 0.08)).offset(x: -s * 0.40, y: s * 0.12)
            }.foregroundStyle(IslandTheme.sun.opacity(0.95))
                .transition(.scale(scale: 0.2).combined(with: .opacity))
        case .dizzy:
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "star.fill").font(.system(size: s * 0.09)).foregroundStyle(IslandTheme.sun)
                        .offset(x: s * 0.30)
                        .rotationEffect(.degrees(orbit + Double(i) * 120))
                }
            }.scaleEffect(x: 1, y: 0.4).offset(y: -s * 0.42)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private func particles(_ s: CGFloat) -> some View {
        if let particle {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let dx: CGFloat = CGFloat(i - 1) * s * 0.28
                    Image(systemName: particle.symbol)
                        .font(.system(size: s * (i == 1 ? 0.16 : 0.12), weight: .bold))
                        .foregroundStyle(particle.color)
                        .offset(x: burst == 2 ? dx : dx * 0.3, y: burst == 2 ? -s * 0.62 : -s * 0.25)
                        .scaleEffect(burst == 0 ? 0.3 : 1)
                        .opacity(burst == 1 ? 1 : 0)
                }
            }
        }
    }

    // MARK: Choreography

    private func pause(_ ms: Int) async throws {
        try await Task.sleep(for: .milliseconds(ms))
    }

    /// Sleeps, then stops this run if a newer action has taken over the pose.
    private func hold(_ ms: Int, _ id: UUID) async throws {
        try await Task.sleep(for: .milliseconds(ms))
        if runID != id { throw CancellationError() }
    }

    private func perform(_ action: CompanionAction) async {
        guard motion else { return }
        let id = UUID()
        runID = id
        busy = true
        do { try await run(action, id) } catch {
            // Interrupted. A newer action, if any, now owns the pose.
        }
        guard runID == id else { return }
        rest()
        busy = false
    }

    private func rest() {
        var instant = Transaction()
        instant.disablesAnimations = true
        // Whole turns look identical, so drop them without animating backwards.
        withTransaction(instant) { spin = spin.truncatingRemainder(dividingBy: 360) }
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) {
            hop = 0; squash = 1; tilt = 0; shake = 0; arms = 0; waveArm = 0; spin = 0
            expression = nil; blink = false
        }
    }

    private func run(_ action: CompanionAction, _ id: UUID) async throws {
        switch action {
        case .hop:
            try await jump(0.16, id)
            try await wave(2, id)
        case .wave:
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { tilt = -6 }
            try await wave(3, id)
        case .giggle:
            expression = .giggle
            for i in 0..<6 {
                withAnimation(.spring(duration: 0.12, bounce: 0.2)) {
                    shake = i.isMultiple(of: 2) ? 0.04 : -0.04
                    squash = i.isMultiple(of: 2) ? 0.96 : 1.03
                }
                try await hold(110, id)
            }
        case .spin:
            expression = .excited
            withAnimation(.easeOut(duration: 0.12)) { squash = 0.88 }
            try await hold(120, id)
            withAnimation(.spring(duration: 0.7, bounce: 0.25)) { spin = 360; hop = -0.12; squash = 1.05 }
            try await hold(420, id)
            withAnimation(.spring(duration: 0.35, bounce: 0.5)) { hop = 0; squash = 0.94 }
            try await hold(260, id)
        case .wink:
            withAnimation(.spring(duration: 0.25, bounce: 0.3)) { expression = .wink; tilt = 8 }
            try await hold(800, id)
        case .surprised:
            withAnimation(.spring(duration: 0.18, bounce: 0.5)) { expression = .surprised; hop = -0.10; squash = 1.1; arms = 70 }
            try await hold(220, id)
            withAnimation(.spring(duration: 0.35, bounce: 0.5)) { hop = 0; squash = 1 }
            try await hold(600, id)
        case .dance:
            expression = .excited
            startBurst(.notes)
            for beat in 0..<6 {
                withAnimation(.spring(duration: 0.22, bounce: 0.55)) {
                    tilt = beat.isMultiple(of: 2) ? -14 : 14
                    hop = beat.isMultiple(of: 2) ? -0.08 : 0
                    squash = beat.isMultiple(of: 2) ? 1.06 : 0.95
                    arms = beat.isMultiple(of: 2) ? 90 : 20
                }
                try await hold(170, id)
            }
        case .love:
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { expression = .love; squash = 0.92; arms = 110 }
            startBurst(.hearts)
            try await hold(1000, id)
        case .dizzy:
            withAnimation(.spring(duration: 0.3)) { expression = .dizzy }
            withAnimation(.easeInOut(duration: 1.4)) { orbit += 720 }
            for i in 0..<4 {
                withAnimation(.easeInOut(duration: 0.3)) { tilt = i.isMultiple(of: 2) ? -10 : 10 }
                try await hold(300, id)
            }
        case .stretch:
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) { arms = 140; squash = 1.08 }
            try await hold(650, id)
            withAnimation(.spring(duration: 0.3, bounce: 0.5)) { squash = 0.95 }
            try await hold(200, id)
        case .celebrate:
            expression = .excited
            startBurst(.stars)
            try await jump(0.2, id, armsUp: true)
            try await jump(0.12, id, armsUp: true)
        case .yawn:
            withAnimation(.easeInOut(duration: 0.4)) { expression = .yawn; squash = 1.06; arms = 60 }
            try await hold(900, id)
        case .sigh:
            withAnimation(.easeInOut(duration: 0.5)) { squash = 0.92; tilt = -4 }
            try await hold(700, id)
        }
    }

    private func jump(_ height: CGFloat, _ id: UUID, armsUp: Bool = false) async throws {
        withAnimation(.easeOut(duration: 0.09)) { squash = 0.86 }
        try await hold(90, id)
        withAnimation(.spring(duration: 0.3, bounce: 0.4)) {
            hop = -height; squash = 1.07
            if armsUp { arms = 120 }
        }
        try await hold(230, id)
        withAnimation(.spring(duration: 0.22, bounce: 0.3)) { hop = 0; squash = 0.92 }
        try await hold(140, id)
        withAnimation(.spring(duration: 0.3, bounce: 0.5)) { squash = 1 }
    }

    private func wave(_ times: Int, _ id: UUID) async throws {
        for i in 0..<(times * 2) {
            withAnimation(.spring(duration: 0.18, bounce: 0.4)) { waveArm = i.isMultiple(of: 2) ? 110 : 70 }
            try await hold(170, id)
        }
    }

    private func startBurst(_ kind: CompanionParticle) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { particle = kind; burst = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.easeOut(duration: 0.9)) { burst = 2 }
        }
    }

    // MARK: Idle life

    /// One-shot mood extras (a tear rolls, "z"s float up), then, when lively, a calm
    /// loop of breathing, blinks, glances and the odd stretch or yawn.
    private func live() async {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { drift = false; glance = .zero; blink = false }
        guard motion else { withTransaction(instant) { breathe = false }; return }
        if mood == .sad || mood == .sleepy {
            do { try await pause(250) } catch { return }
            withAnimation(.easeInOut(duration: 1.4)) { drift = true }
        }
        guard lively else { withTransaction(instant) { breathe = false }; return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        while !Task.isCancelled {
            do { try await pause(Int.random(in: 2200...4600)) } catch { break }
            if busy { continue }
            do { try await idleBeat() } catch { break }
        }
        withTransaction(instant) { breathe = false; glance = .zero; blink = false }
    }

    private func idleBeat() async throws {
        let roll = Int.random(in: 0..<100)
        if mood == .sleepy {
            // Dozing: the "z"s drift up again, with the occasional yawn.
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) { drift = false }
            try await pause(30)
            withAnimation(.easeInOut(duration: 1.6)) { drift = true }
            if roll < 20 { await perform(.yawn) }
            return
        }
        switch roll {
        case 0..<50:
            try await blinkOnce()
        case 50..<75:
            try await glanceAround()
        case 75..<84:
            await perform(.stretch)
        case 84..<92:
            try await blinkOnce()
            try await pause(140)
            try await blinkOnce()
        default:
            if mood == .sad || mood == .worried { await perform(.sigh) } else { try await glanceAround() }
        }
    }

    private func blinkOnce() async throws {
        withAnimation(.easeInOut(duration: 0.07)) { blink = true }
        try await pause(110)
        withAnimation(.easeInOut(duration: 0.09)) { blink = false }
    }

    private func glanceAround() async throws {
        let target = CGSize(width: Bool.random() ? 0.9 : -0.9, height: CGFloat.random(in: -0.4...0.3))
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) { glance = target }
        try await pause(Int.random(in: 700...1300))
        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { glance = .zero }
    }
}

// MARK: - Interactive companion

/// Remembers which companions already greeted the user during this launch.
@MainActor private enum CompanionSession {
    static var greeted: Set<String> = []
}

private struct CompanionTouch: Equatable {
    var translation: CGSize = .zero
    var location: CGPoint?
}

/// The companion with touch: tap for varied reactions, drag to make it look toward your
/// finger and squish (it springs back), hold for a hug, and tap quickly to make it dizzy.
/// Decorative for VoiceOver. Hosts keep it clear of important information and controls.
struct InteractiveCompanion: View {
    var mood: IslandMood = .happy
    var size: CGFloat = 76
    /// A new value plays a celebration (for example, after a save).
    var cheer: UUID? = nil
    /// Played when the companion first appears.
    var greeting: CompanionAction? = nil
    /// When set, the greeting plays once per launch for this key.
    var greetKey: String? = nil
    /// Receives a short line when the user plays with the companion.
    var onSpeak: ((String) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @AppStorage("playfulAnimations") private var playful = true
    @AppStorage("ambientAnimations") private var ambient = true
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.5, bounce: 0.55)))
    private var touch = CompanionTouch()
    @State private var cue: CompanionCue?
    @State private var visible = false
    @State private var taps: [Date] = []
    @State private var lastAction: CompanionAction?
    @State private var holdTask: Task<Void, Never>?
    @State private var hugged = false

    private var lively: Bool {
        visible && phase == .active && IslandAmbient.allowed(playful: playful, ambient: ambient, reduceMotion: reduceMotion)
    }
    private var look: CGSize {
        guard let point = touch.location, !reduceMotion else { return .zero }
        let half = size / 2
        return CGSize(width: max(-1, min(1, (point.x - half) / half)), height: max(-1, min(1, (point.y - half) / half)))
    }
    private var pull: CGSize {
        guard !reduceMotion, playful else { return .zero }
        return CGSize(width: rubber(touch.translation.width), height: rubber(touch.translation.height))
    }

    var body: some View {
        MoonIslandMascot(mood: mood, cue: cue, look: look, lively: lively)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(Double(pull.width) * 0.8), anchor: .bottom)
            .offset(pull)
            // A fixed outer frame keeps the gesture's coordinate space still while the
            // companion stretches, so the pull can't feed back into the drag reading.
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(drag)
            .accessibilityHidden(true)
            .onAppear { visible = true; greet() }
            .onDisappear { visible = false; holdTask?.cancel(); holdTask = nil }
            .onChange(of: cheer) { _, value in if value != nil { play(.celebrate, speak: false, sound: false) } }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touch) { value, state, _ in
                state.translation = value.translation
                state.location = value.location
            }
            .onChanged { _ in startHoldTimer() }
            .onEnded { value in finish(value) }
    }

    /// Stretchy, bounded pull that resists more the further you drag.
    private func rubber(_ value: CGFloat) -> CGFloat {
        let limit = size * 0.22
        return value / (1 + abs(value) / limit)
    }

    private func startHoldTimer() {
        guard holdTask == nil, !hugged else { return }
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            defer { holdTask = nil }
            guard !Task.isCancelled, touch.location != nil,
                  abs(touch.translation.width) < 10, abs(touch.translation.height) < 10 else { return }
            hugged = true
            play(.love)
        }
    }

    private func finish(_ value: DragGesture.Value) {
        holdTask?.cancel(); holdTask = nil
        if hugged { hugged = false; return }
        let distance = hypot(value.translation.width, value.translation.height)
        if distance < 10 { tapped() }
        else if distance > size * 0.5 { play(.giggle) } // Stretched far: it boings back, giggling.
    }

    private func tapped() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 2.5 } + [now]
        if taps.count >= 5 {
            taps = []
            play(.dizzy)
            return
        }
        if mood == .sleepy && lastAction == nil {
            play(.yawn)
            return
        }
        let options = CompanionAction.tapReactions.filter { $0 != lastAction }
        play(options.randomElement() ?? .wave)
    }

    private func greet() {
        guard let greeting else { return }
        if let greetKey {
            guard !CompanionSession.greeted.contains(greetKey) else { return }
            CompanionSession.greeted.insert(greetKey)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard visible else { return }
            cue = CompanionCue(action: greeting)
        }
    }

    private func play(_ action: CompanionAction, speak: Bool = true, sound: Bool = true) {
        lastAction = action
        cue = CompanionCue(action: action)
        switch action {
        case .celebrate: FeedbackHaptics.success()
        case .love, .dizzy: FeedbackHaptics.pop()
        default: FeedbackHaptics.tap()
        }
        if sound { CompanionVoice.play(action) }
        if speak, let line = CompanionLines.line(for: action) { onSpeak?(line) }
    }
}

// MARK: - Voice

/// Optional sounds for user-triggered reactions. Respects the sound settings.
enum CompanionVoice {
    @MainActor static func play(_ action: CompanionAction) {
        let cue: FeedbackSounds.Cue
        switch action {
        case .wave, .hop, .wink, .surprised, .stretch, .yawn: cue = .hello
        case .love, .sigh: cue = .hug
        case .dance, .giggle, .spin: cue = .dance
        case .celebrate, .dizzy: cue = .star
        }
        FeedbackSounds.shared.play(cue)
    }
}

/// Warm, varied lines the companion says when you play with it.
enum CompanionLines {
    static func line(for action: CompanionAction) -> String? {
        let options: [String]
        switch action {
        case .wave:
            options = [tr("嗨！很高兴见到你！", "Hi there! Good to see you!", "Hai! Gembira jumpa anda!"),
                       tr("又见面啦！", "Hello again!", "Helo lagi!")]
        case .hop:
            options = [tr("蹦蹦跳跳！", "Boing boing!", "Lompat, lompat!")]
        case .giggle:
            options = [tr("嘻嘻，好痒！", "Hehe, that tickles!", "Hehe, gelinya!"),
                       tr("哈哈，别闹啦！", "Haha, stop it!", "Haha, sudahlah!")]
        case .spin:
            options = [tr("转圈圈～", "Wheee!", "Wiii!")]
        case .wink:
            options = [tr("悄悄告诉你：你做得很好。", "Psst… you’re doing great.", "Psst… anda hebat."),
                       tr("记账这件事，你越来越拿手啦！", "You’re getting so good at this!", "Anda makin pandai!")]
        case .surprised:
            options = [tr("哇！被你找到了！", "Oh! You found me!", "Oh! Anda jumpa saya!")]
        case .dance:
            options = [tr("一起跳舞吧！", "Let’s dance!", "Jom menari!"),
                       tr("啦啦啦～", "La la la~", "La la la~")]
        case .love:
            options = [tr("抱抱！谢谢你认真照顾自己的钱。", "A hug! Thanks for caring for your money.", "Peluk! Terima kasih menjaga wang anda."),
                       tr("有你真好！", "So glad you’re here!", "Seronok anda di sini!")]
        case .dizzy:
            options = [tr("哇……转得头好晕！", "Whoa… so dizzy!", "Wah… peningnya!")]
        case .yawn:
            options = [tr("哈欠……啊，你来啦！", "Yawn… oh, hello!", "Menguap… oh, helo!")]
        case .stretch:
            options = [tr("伸个懒腰～", "Big stretch!", "Regangan besar!")]
        case .celebrate:
            options = [tr("太棒了！", "Woohoo!", "Hore!")]
        case .sigh:
            options = [tr("没关系，慢慢来。", "It’s okay. One step at a time.", "Tak apa. Selangkah demi selangkah.")]
        }
        return options.randomElement()
    }
}

// MARK: - Page banner

/// A page header with the companion. Tapping it shows a short line in place of the subtitle.
struct IslandPageBanner: View {
    let title: String
    let subtitle: String
    var symbol: String = "sparkles"
    var mood: IslandMood = .happy
    /// Optional chip under the subtitle.
    var badge: AnyView? = nil
    /// Each new value makes the companion celebrate (for example, after a save).
    var cheer: UUID? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("playfulAnimations") private var playful = true
    @State private var entered = false
    @State private var spoken: String?
    @State private var spokenID = UUID()
    private var shownLine: String { spoken ?? subtitle }
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(IslandTheme.accent)
                Text(shownLine)
                    .font(.subheadline.weight(spoken == nil ? .regular : .semibold))
                    .foregroundStyle(spoken == nil ? Color.secondary : IslandTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(shownLine)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .leading).combined(with: .opacity))
                if let badge { badge }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3), value: shownLine)
            if !typeSize.isAccessibilitySize {
                InteractiveCompanion(mood: mood, size: 76, cheer: cheer, onSpeak: speak)
                    .rotationEffect(.degrees(entered || reduceMotion || !playful ? -7 : 8))
                    .scaleEffect(entered || reduceMotion || !playful ? 1 : 0.85)
            }
        }.padding(18)
            .background(IslandTheme.sun.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(IslandTheme.line, lineWidth: 1.5))
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            .task {
                guard !entered else { return }
                guard !reduceMotion, playful else { entered = true; return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.22)) { entered = true }
            }
            .task(id: spokenID) {
                guard spoken != nil else { return }
                do { try await Task.sleep(for: .seconds(3.5)) } catch { return }
                spoken = nil
            }
    }
    private func speak(_ line: String) {
        spoken = line
        spokenID = UUID()
    }
}

// MARK: - Loading

/// Shown while the ledger loads when the opening animation is turned off.
struct IslandLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            InteractiveCompanion(mood: .happy, size: 96, greeting: .wave)
            Text(tr("正在打开你的小岛…", "Opening your island…", "Membuka pulau anda…"))
                .font(.headline).foregroundStyle(IslandTheme.accent)
            ProgressView().controlSize(.small)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("正在读取账本", "Loading ledger", "Memuatkan lejar"))
    }
}
