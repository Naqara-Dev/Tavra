import SwiftUI

/// Tavra's motion, in one place. The idea throughout: light follows touch. It pools under a finger,
/// runs along an edge, and goes round the trackpad when everything checks out. Nothing moves on its
/// own unless it's asking for something, so an idle window costs nothing.
enum Motion {
    static let glide = Animation.spring(response: 0.36, dampingFraction: 0.8)
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let snap = Animation.spring(response: 0.26, dampingFraction: 0.72)
}

/// Fingers on the trackpad: a soft head with a fading trail, a ripple where it lands, and light pooling
/// inside whichever zone it's in. It only redraws when a finger has moved.
struct TouchField: View {
    var router: GestureRouter
    var size: CGSize
    /// Where light may pool.
    var zones: [CGRect] = []

    private struct Trail: Equatable {
        var points: [CGPoint]
        var lifted = false
    }

    private struct Ripple: Identifiable {
        let id = UUID()
        var at: CGPoint
        var strong: Bool
    }

    @State private var trails: [Int64: Trail] = [:]
    @State private var busy = false
    @State private var ripples: [Ripple] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let trailLength = 14
    private static let jump: CGFloat = 110

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for trail in trails.values {
                    guard let head = trail.points.last else { continue }
                    let strength = trail.lifted ? Double(trail.points.count) / Double(Self.trailLength) : 1
                    pool(in: &context, at: head, strength: strength)
                    tail(in: &context, trail.points, strength: strength)
                    tip(in: &context, at: head, strength: strength)
                }
            }
            ForEach(ripples) { ripple in
                RippleRing(strong: ripple.strong).position(ripple.at)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .task { await follow() }
    }

    private func pool(in context: inout GraphicsContext, at head: CGPoint, strength: Double) {
        let radius: CGFloat = busy ? 130 : 90
        for rect in zones where rect.contains(head) {
            var clipped = context
            clipped.clip(to: Path(rect))
            clipped.fill(Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [Theme.accent.opacity((busy ? 0.6 : 0.32) * strength), Theme.accent.opacity(0)]),
                                               center: head, startRadius: 0, endRadius: radius))
        }
    }

    private func tail(in context: inout GraphicsContext, _ points: [CGPoint], strength: Double) {
        guard points.count > 1 else { return }
        for index in 1..<points.count {
            var segment = Path()
            segment.move(to: points[index - 1])
            segment.addLine(to: points[index])
            let progress = Double(index) / Double(points.count)
            context.stroke(segment, with: .color(Theme.accent.opacity(progress * 0.55 * strength)),
                           style: StrokeStyle(lineWidth: 1 + progress * 7, lineCap: .round))
        }
    }

    private func tip(in context: inout GraphicsContext, at head: CGPoint, strength: Double) {
        let glow: CGFloat = busy ? 30 : 22
        context.fill(Path(ellipseIn: CGRect(x: head.x - glow, y: head.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [Theme.accent.opacity(0.55 * strength), Theme.accent.opacity(0)]), center: head, startRadius: 0, endRadius: glow))
        let core: CGFloat = busy ? 6 : 8
        context.fill(Path(ellipseIn: CGRect(x: head.x - core, y: head.y - core, width: core * 2, height: core * 2)), with: .color(Theme.ink.opacity(0.95 * strength)))
    }

    private func point(_ finger: Finger) -> CGPoint {
        CGPoint(x: finger.x * size.width, y: (1 - finger.y) * size.height)
    }

    private func follow() async {
        while !Task.isCancelled {
            let state = router.snapshot()
            var next = trails
            let live = Set(state.fingers.map(\.id))
            for finger in state.fingers {
                let at = point(finger)
                var trail = next[finger.id] ?? Trail(points: [])
                // Further than any finger travels between two looks: it lifted and landed somewhere else.
                if let last = trail.points.last, hypot(last.x - at.x, last.y - at.y) > Self.jump || trail.lifted { trail.points = [] }
                if trail.points.isEmpty, !reduceMotion { addRipple(at: at, strong: false) }
                if let last = trail.points.last, hypot(last.x - at.x, last.y - at.y) < 0.5 {
                    // Still: the tail catches up with the head.
                    if trail.points.count > 1 { trail.points.removeFirst() }
                } else {
                    trail.points.append(at)
                    if trail.points.count > Self.trailLength { trail.points.removeFirst() }
                }
                trail.lifted = false
                next[finger.id] = trail
            }
            // A lifted finger fades out instead of vanishing.
            for (id, var trail) in next where !live.contains(id) {
                if trail.lifted, trail.points.count <= 2 {
                    next[id] = nil
                } else {
                    if !trail.lifted, trail.points.count < Self.trailLength {
                        // Long enough to fade from.
                        trail.points = Array(repeating: trail.points.first ?? .zero, count: Self.trailLength - trail.points.count) + trail.points
                    }
                    trail.lifted = true
                    trail.points.removeFirst(min(2, trail.points.count))
                    next[id] = trail
                }
            }
            if state.busy != busy {
                if state.busy, !reduceMotion, let head = next.values.first?.points.last { addRipple(at: head, strong: true) }
                withAnimation(Motion.snap) { busy = state.busy }
            }
            if next != trails { trails = next }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    private func addRipple(at: CGPoint, strong: Bool) {
        let ripple = Ripple(at: at, strong: strong)
        ripples.append(ripple)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            ripples.removeAll { $0.id == ripple.id }
        }
    }
}

private struct RippleRing: View {
    var strong: Bool
    @State private var open = false

    var body: some View {
        Circle()
            .strokeBorder(Theme.accent, lineWidth: strong ? 2 : 1.2)
            .frame(width: 44, height: 44)
            .scaleEffect(open ? (strong ? 3.1 : 2.1) : 0.35)
            .opacity(open ? 0 : (strong ? 0.9 : 0.6))
            .onAppear { withAnimation(.easeOut(duration: strong ? 0.75 : 0.6)) { open = true } }
    }
}

/// The picked zone's frame glides from one zone to the next.
struct SelectionFrame: View {
    var rect: CGRect

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Theme.accent.opacity(0.16))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.accent.opacity(0.85), lineWidth: 1.2))
            .shadow(color: Theme.accent.opacity(0.5), radius: 12)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .animation(Motion.glide, value: rect)
    }
}

/// An edge in the trackpad check. Asked for: a current runs along it. Found: it charges up from the
/// middle with a flash, and stays lit.
struct ChargingStrip: View {
    var isFound: Bool
    var isAsked: Bool
    var isVertical: Bool

    @State private var flowing = false
    @State private var charged = false
    @State private var flash = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let length = isVertical ? geometry.size.height : geometry.size.width
            ZStack {
                if isAsked, !isFound {
                    Rectangle().fill(Theme.accent.opacity(0.1))
                    if !reduceMotion {
                        Rectangle()
                            .fill(LinearGradient(colors: [Theme.accent.opacity(0), Theme.accent.opacity(0.7), Theme.accent.opacity(0)],
                                                 startPoint: isVertical ? .bottom : .leading, endPoint: isVertical ? .top : .trailing))
                            .frame(width: isVertical ? nil : length * 0.5, height: isVertical ? length * 0.5 : nil)
                            .offset(x: isVertical ? 0 : (flowing ? length * 0.75 : -length * 0.75),
                                    y: isVertical ? (flowing ? -length * 0.75 : length * 0.75) : 0)
                    }
                }
                Rectangle().fill(Theme.accent.opacity(0.48))
                    .scaleEffect(x: isVertical || charged ? 1 : 0.001, y: !isVertical || charged ? 1 : 0.001)
                    .opacity(charged ? 1 : 0)
                Rectangle().fill(Color.white).opacity(flash ? 0.55 : 0)
                Rectangle().strokeBorder(isFound || isAsked ? Theme.accent.opacity(0.6) : Theme.line, lineWidth: 1)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .onAppear {
            charged = isFound
            startFlow()
        }
        .onChange(of: isAsked) { startFlow() }
        .onChange(of: isFound) {
            guard isFound else {
                charged = false
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { charged = true }
            flash = true
            withAnimation(.easeOut(duration: 0.65)) { flash = false }
        }
    }

    private func startFlow() {
        flowing = false
        guard isAsked, !reduceMotion else { return }
        withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { flowing = true }
    }
}

/// A short stretch of the outline, somewhere along its length.
private struct OutlineStretch: Shape {
    var cornerRadius: CGFloat
    var phase: Double
    var span: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
            .trimmedPath(from: max(phase - span, 0), to: min(phase, 1))
    }
}

/// Everything read: light runs once round the trackpad, leaves the outline lit, and draws a check.
struct CompletionLight: View {
    var cornerRadius: CGFloat = 22
    @State private var phase = 0.0
    @State private var lit = false
    @State private var drawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5)
                .opacity(lit ? 0.9 : 0)
            OutlineStretch(cornerRadius: cornerRadius, phase: phase, span: 0.22)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .shadow(color: Theme.accent, radius: 10)
                .opacity(phase >= 1 ? 0 : 1)
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(width: 46, height: 36)
                .shadow(color: Theme.accent.opacity(0.7), radius: 10)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else {
                phase = 1
                lit = true
                drawn = true
                return
            }
            withAnimation(.easeInOut(duration: 1.05)) { phase = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.8)) { lit = true }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.7)) { drawn = true }
        }
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// A line of words that come into focus one after another.
struct WordReveal: View {
    var text: String
    var size: CGFloat
    @State private var shown = false

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.24) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(.system(size: size, weight: .light)).tracking(-0.8).foregroundStyle(Theme.ink)
                    .opacity(shown ? 1 : 0)
                    .blur(radius: shown ? 0 : 7)
                    .offset(y: shown ? 0 : 10)
                    .animation(Motion.settle.delay(0.35 + Double(index) * 0.07), value: shown)
            }
        }
        .onAppear { shown = true }
    }
}

/// Comes into focus after a moment, for things that arrive in sequence.
struct Arrive: ViewModifier {
    var delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 5)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear { withAnimation(Motion.settle.delay(reduceMotion ? 0 : delay)) { shown = true } }
    }
}

extension View {
    func arrive(after delay: Double) -> some View { modifier(Arrive(delay: delay)) }
}

/// The welcome: a trackpad draws itself, a finger lands on its edge, and the edge lights up.
struct IntroMark: View {
    @State private var drawn = false
    @State private var edgeLit = false
    @State private var landed = false
    @State private var slid = false
    @State private var rippled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size = CGSize(width: 104, height: 66)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Theme.card.opacity(drawn ? 0.8 : 0))
            OutlineStretch(cornerRadius: 13, phase: drawn ? 1 : 0, span: 1)
                .stroke(Theme.ink.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            // The lit edge, rising from the bottom.
            Capsule()
                .fill(LinearGradient(colors: [Theme.cool, Theme.accent], startPoint: .bottom, endPoint: .top))
                .frame(width: 4, height: 46)
                .scaleEffect(y: edgeLit ? 1 : 0.001, anchor: .bottom)
                .shadow(color: Theme.accent, radius: edgeLit ? 8 : 0)
                .offset(x: size.width - 11, y: 10)
            // The fingertip.
            Circle().strokeBorder(Theme.accent, lineWidth: 1.2)
                .frame(width: 14, height: 14)
                .scaleEffect(rippled ? 3 : 0.4)
                .opacity(rippled ? 0 : (landed ? 0.8 : 0))
                .offset(x: size.width - 16, y: 42)
            Circle().fill(Theme.ink)
                .frame(width: 11, height: 11)
                .shadow(color: Theme.accent, radius: 8)
                .scaleEffect(landed ? 1 : 0.2)
                .opacity(landed ? 1 : 0)
                .offset(x: size.width - 14.5, y: slid ? 14 : 44)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onAppear {
            guard !reduceMotion else {
                drawn = true
                edgeLit = true
                landed = true
                slid = true
                return
            }
            withAnimation(.easeInOut(duration: 0.75)) { drawn = true }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.65)) { landed = true }
            withAnimation(.easeOut(duration: 0.7).delay(0.7)) { rippled = true }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.85)) {
                slid = true
                edgeLit = true
            }
        }
    }
}
