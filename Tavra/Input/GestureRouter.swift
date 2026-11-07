import Foundation
import os

/// The one place touches and clicks meet. Touches arrive on the multitouch thread and clicks on the
/// event tap's, so the engine sits behind a lock, and what it asks for is done on the main thread.
final class GestureRouter: @unchecked Sendable {
    private struct State {
        var engine = GestureEngine()
        var config = Config()
        var front: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let ticks = DispatchQueue(label: "com.naqara.tavra.ticks")
    private var ticking = false
    /// Called on the main thread.
    var onEffects: @MainActor @Sendable ([Effect]) -> Void = { _ in }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func update(_ config: Config) {
        state.withLock {
            $0.config = config
            $0.engine.feel = config.feel
        }
    }

    func setFrontApp(_ bundleID: String?) {
        state.withLock { $0.front = bundleID }
    }

    /// For drawing. Cheap, and only asked while a window is showing.
    func snapshot() -> (fingers: [Finger], surface: Surface, busy: Bool) {
        state.withLock { ($0.engine.fingers, $0.engine.surface, $0.engine.isBusy) }
    }

    func touches(_ fingers: [Finger], surface: Surface) {
        let time = now
        deliver(state.withLock { $0.engine.touches(fingers, surface: surface, now: time) })
    }

    func mouseDown(flags: UInt64) -> Bool {
        let time = now
        let result = state.withLock { state -> (swallow: Bool, effects: [Effect]) in
            let bindings = state.config.bindings(forApp: state.front)
            return state.engine.mouseDown(flags: flags, bindings: bindings, now: time)
        }
        deliver(result.effects)
        keepTicking()
        return result.swallow
    }

    func mouseDragged(flags: UInt64) -> Bool {
        let time = now
        return state.withLock { $0.engine.mouseDragged(flags: flags, now: time) }
    }

    func mouseUp() -> Bool {
        let time = now
        let result = state.withLock { $0.engine.mouseUp(now: time) }
        deliver(result.effects)
        keepTicking()
        return result.swallow
    }

    /// macOS turned the tap off, the Mac slept, or Tavra is quitting: nothing may stay held.
    func reset() {
        deliver(state.withLock { $0.engine.reset() })
    }

    /// Runs only while something's going on, so an idle Tavra costs nothing.
    private func keepTicking() {
        ticks.async { [self] in
            guard !ticking else { return }
            ticking = true
            tick()
        }
    }

    private func tick() {
        let time = now
        let result = state.withLock { ($0.engine.tick(now: time), $0.engine.isBusy) }
        deliver(result.0)
        guard result.1 else {
            ticking = false
            return
        }
        ticks.asyncAfter(deadline: .now() + 0.05) { [self] in tick() }
    }

    private func deliver(_ effects: [Effect]) {
        guard !effects.isEmpty else { return }
        let handler = onEffects
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(effects) } }
    }
}
