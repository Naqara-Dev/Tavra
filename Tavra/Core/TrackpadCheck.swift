import Foundation

/// Walks someone round the trackpad to show that every edge reads. It only looks at where a finger is,
/// so it works before Tavra has any permission at all, and nothing gets clicked.
struct TrackpadCheck: Sendable, Equatable {
    static let order: [Zone] = [.right, .left, .bottom, .top]
    /// A finger has to stay this long, so brushing past an edge on the way to another doesn't count.
    static let dwellSeconds = 0.12
    /// How long a wait on one edge before suggesting something.
    static let hintAfterSeconds = 10.0

    private(set) var found: [Zone] = []
    private var holding: (zone: Zone, since: TimeInterval)?
    private var waitingSince: TimeInterval?

    var current: Zone? { Self.order.first { !found.contains($0) } }
    var isDone: Bool { current == nil }

    /// Which edge a point is on, if any: the nearest, where two meet.
    static func edge(x: Double, y: Double, surface: Surface, feel: FeelSettings) -> Zone? {
        order.map { (zone: $0, depth: Geometry.depth($0, x: x, y: y, surface: surface)) }
            .filter { $0.depth <= feel.edgeMM }
            .min { $0.depth < $1.depth }?.zone
    }

    /// Whether it's been a while on this edge with nothing read.
    func needsHint(now: TimeInterval) -> Bool {
        guard !isDone, let waitingSince else { return false }
        return now - waitingSince >= Self.hintAfterSeconds
    }

    /// True when an edge was just found. Any edge counts, in any order: nobody should be made to redo
    /// one because they got ahead of the instructions.
    mutating func update(fingers: [Finger], surface: Surface, feel: FeelSettings, now: TimeInterval) -> Bool {
        if waitingSince == nil { waitingSince = now }
        guard fingers.count == 1, let finger = fingers.first,
              let zone = Self.edge(x: finger.x, y: finger.y, surface: surface, feel: feel), !found.contains(zone) else {
            holding = nil
            return false
        }
        guard let held = holding, held.zone == zone else {
            holding = (zone, now)
            return false
        }
        guard now - held.since >= Self.dwellSeconds else { return false }
        found.append(zone)
        holding = nil
        waitingSince = now
        return true
    }

    static func == (lhs: TrackpadCheck, rhs: TrackpadCheck) -> Bool { lhs.found == rhs.found }
}
