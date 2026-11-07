import Foundation

/// A trackpad's size. Everything is measured in millimetres, so a slide feels the same on any of them.
struct Surface: Sendable, Equatable {
    var widthMM: Double
    var heightMM: Double

    static let builtIn = Surface(widthMM: 124.8, heightMM: 76.8)
}

/// One finger, in 0...1 across the surface, with y counted from the bottom.
struct Finger: Sendable, Equatable {
    var id: Int64
    var x: Double
    var y: Double
}

/// Where each zone sits, and which one a point belongs to.
enum Geometry {
    /// In 0...1, y from the bottom.
    struct Rect: Sendable, Equatable {
        var minX, minY, maxX, maxY: Double
    }

    static func rect(_ zone: Zone, surface: Surface, feel: FeelSettings) -> Rect {
        let ex = min(feel.edgeMM / surface.widthMM, 0.5), ey = min(feel.edgeMM / surface.heightMM, 0.5)
        let cx = min(feel.cornerMM / surface.widthMM, 0.5), cy = min(feel.cornerMM / surface.heightMM, 0.5)
        switch zone {
        case .left: return Rect(minX: 0, minY: 0, maxX: ex, maxY: feel.sideSpan)
        case .right: return Rect(minX: 1 - ex, minY: 0, maxX: 1, maxY: feel.sideSpan)
        case .top: return Rect(minX: 0, minY: 1 - ey, maxX: 1, maxY: 1)
        case .bottom: return Rect(minX: 0, minY: 0, maxX: 1, maxY: ey)
        case .topLeft: return Rect(minX: 0, minY: 1 - cy, maxX: cx, maxY: 1)
        case .topRight: return Rect(minX: 1 - cx, minY: 1 - cy, maxX: 1, maxY: 1)
        case .bottomLeft: return Rect(minX: 0, minY: 0, maxX: cx, maxY: cy)
        case .bottomRight: return Rect(minX: 1 - cx, minY: 0, maxX: 1, maxY: cy)
        }
    }

    private static func contains(_ r: Rect, x: Double, y: Double) -> Bool {
        x >= r.minX && x <= r.maxX && y >= r.minY && y <= r.maxY
    }

    /// A corner with a job wins. Otherwise it's the nearest edge with a job, and a corner or edge
    /// without one stays an ordinary part of the trackpad.
    static func zone(x: Double, y: Double, surface: Surface, feel: FeelSettings, bindings: Bindings) -> Zone? {
        for corner in Zone.corners where bindings.has(corner) {
            if contains(rect(corner, surface: surface, feel: feel), x: x, y: y) { return corner }
        }
        var best: (zone: Zone, distance: Double)?
        for edge in Zone.edges where bindings.has(edge) && contains(rect(edge, surface: surface, feel: feel), x: x, y: y) {
            let distance = depth(edge, x: x, y: y, surface: surface)
            if best == nil || distance < best!.distance { best = (edge, distance) }
        }
        return best?.zone
    }

    /// How far in from its own edge a point is, in millimetres.
    static func depth(_ edge: Zone, x: Double, y: Double, surface: Surface) -> Double {
        switch edge {
        case .left: x * surface.widthMM
        case .right: (1 - x) * surface.widthMM
        case .top: (1 - y) * surface.heightMM
        default: y * surface.heightMM
        }
    }
}

/// What the rest of the app has to do.
enum Effect: Sendable, Equatable {
    case began(Zone)
    case ended(Zone)
    case step(SlideAction, up: Bool, fine: Bool)
    case timelineStarted
    /// Seconds from where it was: what would happen if the finger let go now.
    case timelinePreview(Double)
    case timelineCommitted(Double)
    case timelineCancelled
    case tap(TapAction, zone: Zone, clicks: Int)
    case freezePointer(Bool)
    case haptic
}

/// Turns touches and clicks into gestures. It touches nothing on the Mac: it's told what happened and
/// says what should happen, so all of it can be tested without a trackpad.
///
/// The rule that keeps it out of the way: only a physical click, with one finger that landed inside a
/// zone and is still there, starts anything. Every other click goes through untouched.
struct GestureEngine: Sendable {
    /// Past the strip by this much ends a slide, so a finger drifting slightly doesn't.
    static let leaveMarginMM = 4.0
    /// A gesture that hears nothing for this long is over, whatever happened to the rest of the click.
    static let watchdogSeconds = 5.0
    /// Holding one of these keeps a click ordinary, for when an edge click is what's wanted.
    static let bypassFlags = Flag.command | Flag.control
    static let fineFlags = Flag.shift | Flag.option

    private struct Slide: Sendable {
        var zone: Zone
        var action: SlideAction
        var finger: Int64
        var startX: Double
        var startY: Double
        var steps = 0
        var preview = 0.0
    }

    private struct Corner: Sendable {
        var zone: Zone
        var bindings: Bindings
        var clicks: Int
        var isDown: Bool
        var lastUp: TimeInterval
    }

    private enum Mode: Sendable {
        case idle
        case sliding(Slide)
        case corner(Corner)
        /// A gesture ended early. The click it swallowed still has an up to come.
        case waitingForUp
    }

    var feel = FeelSettings()
    private(set) var surface = Surface.builtIn
    private(set) var fingers: [Finger] = []
    private var landings: [Int64: (x: Double, y: Double)] = [:]
    private var mode = Mode.idle
    private var flags: UInt64 = 0
    private var lastHeard: TimeInterval = 0

    var isBusy: Bool {
        if case .idle = mode { return false }
        return true
    }

    // MARK: Touches

    mutating func touches(_ current: [Finger], surface: Surface, now: TimeInterval) -> [Effect] {
        self.surface = surface
        lastHeard = now
        let ids = Set(current.map(\.id))
        landings = landings.filter { ids.contains($0.key) }
        for finger in current where landings[finger.id] == nil { landings[finger.id] = (finger.x, finger.y) }
        fingers = current
        guard case .sliding(var slide) = mode, let finger = current.first(where: { $0.id == slide.finger }) else { return [] }

        if Geometry.depth(slide.zone, x: finger.x, y: finger.y, surface: surface) > feel.edgeMM + Self.leaveMarginMM {
            return finishEarly(slide)
        }
        let isVertical = slide.zone == .left || slide.zone == .right
        var travel = isVertical ? (finger.y - slide.startY) * surface.heightMM : (finger.x - slide.startX) * surface.widthMM
        if feel.invert { travel = -travel }

        var effects: [Effect] = []
        if slide.action == .timeline {
            let seconds = travel / surface.widthMM * feel.timelineSeconds
            if abs(seconds - slide.preview) >= 0.25 {
                slide.preview = seconds
                effects.append(.timelinePreview(seconds))
            }
            let steps = Int(travel / feel.stepMM)
            if steps != slide.steps {
                slide.steps = steps
                effects.append(.haptic)
            }
        } else {
            let target = Int(travel / max(feel.stepMM, 0.5))
            let fine = flags & Self.fineFlags == Self.fineFlags
            while slide.steps != target {
                let up = target > slide.steps
                slide.steps += up ? 1 : -1
                effects.append(.step(slide.action, up: up, fine: fine))
                effects.append(.haptic)
            }
        }
        mode = .sliding(slide)
        return effects
    }

    /// Off the edge: let go of the pointer, drop any seek, and wait for the click to finish.
    private mutating func finishEarly(_ slide: Slide) -> [Effect] {
        mode = .waitingForUp
        var effects: [Effect] = []
        if slide.action == .timeline { effects.append(.timelineCancelled) }
        effects.append(.freezePointer(false))
        effects.append(.ended(slide.zone))
        return effects
    }

    // MARK: The physical click

    /// `bindings` is what's in force right now, nil when Tavra should keep out of the way.
    mutating func mouseDown(flags: UInt64, bindings: Bindings?, now: TimeInterval) -> (swallow: Bool, effects: [Effect]) {
        self.flags = flags
        var effects: [Effect] = []

        if case .corner(var corner) = mode {
            // Another click on the same corner, soon enough.
            if !corner.isDown, zoneUnderOneFinger(corner.bindings) == corner.zone {
                corner.clicks += 1
                corner.isDown = true
                lastHeard = now
                mode = .corner(corner)
                return (true, [])
            }
            effects += resolve(corner)
        }
        if case .sliding = mode {
            // A down with no up seen for the last one. Start clean.
            effects += reset()
        }
        mode = .idle

        guard let bindings, passesModifiers(flags), let zone = zoneUnderOneFinger(bindings), let finger = fingers.first else {
            return (false, effects)
        }
        lastHeard = now
        if zone.isCorner {
            mode = .corner(Corner(zone: zone, bindings: bindings, clicks: 1, isDown: true, lastUp: now))
            return (true, effects + [.began(zone)])
        }
        let action = bindings.slide(zone)
        mode = .sliding(Slide(zone: zone, action: action, finger: finger.id, startX: finger.x, startY: finger.y))
        effects.append(.began(zone))
        if feel.freezePointer { effects.append(.freezePointer(true)) }
        if action == .timeline { effects.append(.timelineStarted) }
        return (true, effects)
    }

    mutating func mouseDragged(flags: UInt64, now: TimeInterval) -> Bool {
        self.flags = flags
        lastHeard = now
        switch mode {
        case .idle: return false
        case .corner(let corner): return corner.isDown
        case .sliding, .waitingForUp: return true
        }
    }

    mutating func mouseUp(now: TimeInterval) -> (swallow: Bool, effects: [Effect]) {
        lastHeard = now
        switch mode {
        case .idle:
            return (false, [])
        case .waitingForUp:
            mode = .idle
            return (true, [])
        case .sliding(let slide):
            mode = .idle
            var effects: [Effect] = []
            if slide.action == .timeline {
                effects.append(abs(slide.preview) >= 1 ? .timelineCommitted(slide.preview) : .timelineCancelled)
            }
            if feel.freezePointer { effects.append(.freezePointer(false)) }
            effects.append(.ended(slide.zone))
            return (true, effects)
        case .corner(var corner):
            guard corner.isDown else { return (false, []) }
            corner.isDown = false
            corner.lastUp = now
            mode = .corner(corner)
            // Nothing more could be meant: don't make it wait.
            if corner.clicks >= (corner.bindings.clickCounts(corner.zone).last ?? 1) {
                return (true, resolve(corner))
            }
            return (true, [])
        }
    }

    /// Runs often. Settles a corner once no further click came, and lets go of a gesture gone silent.
    mutating func tick(now: TimeInterval) -> [Effect] {
        switch mode {
        case .idle:
            return []
        case .corner(let corner) where !corner.isDown:
            return now - corner.lastUp >= feel.multiClickSeconds ? resolve(corner) : []
        default:
            return now - lastHeard >= Self.watchdogSeconds ? reset() : []
        }
    }

    /// Back to nothing, with the pointer free. For a tap macOS turned off, for sleep, for quitting.
    mutating func reset() -> [Effect] {
        var effects: [Effect] = []
        switch mode {
        case .sliding(let slide):
            if slide.action == .timeline { effects.append(.timelineCancelled) }
            effects.append(.freezePointer(false))
            effects.append(.ended(slide.zone))
        case .corner(let corner):
            effects.append(.ended(corner.zone))
        case .idle, .waitingForUp:
            break
        }
        mode = .idle
        return effects
    }

    private mutating func resolve(_ corner: Corner) -> [Effect] {
        mode = .idle
        let action = corner.bindings.tap(corner.zone, clicks: corner.clicks)
        var effects: [Effect] = []
        if action != .none {
            effects.append(.haptic)
            effects.append(.tap(action, zone: corner.zone, clicks: corner.clicks))
        }
        effects.append(.ended(corner.zone))
        return effects
    }

    private func passesModifiers(_ flags: UInt64) -> Bool {
        let required = feel.requiredModifier.flag
        if required != 0 { return flags & required != 0 }
        return flags & Self.bypassFlags == 0
    }

    /// The zone, if exactly one finger is down, it landed in that zone, and it's still there. A
    /// tap-to-click has already lifted by now and a palm makes it two, so neither starts anything.
    private func zoneUnderOneFinger(_ bindings: Bindings) -> Zone? {
        guard fingers.count == 1, let finger = fingers.first, let landing = landings[finger.id] else { return nil }
        let start = Geometry.zone(x: landing.x, y: landing.y, surface: surface, feel: feel, bindings: bindings)
        let here = Geometry.zone(x: finger.x, y: finger.y, surface: surface, feel: feel, bindings: bindings)
        return start == here ? here : nil
    }
}
