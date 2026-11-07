import AppKit
import Foundation
import SwiftUI

/// The bottom edge's job: show where a slide would land, and jump there on letting go.
@MainActor
final class MediaSeeker {
    private let hud = SeekHUD()
    private let scripts = DispatchQueue(label: "com.naqara.tavra.scripts")
    private var route = SeekRoute.nothing
    private var track: (position: Double, duration: Double, title: String)?
    private var feel = FeelSettings()
    private var showHUD = true

    func start(showHUD: Bool, feel: FeelSettings) {
        self.feel = feel
        self.showHUD = showHUD
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        route = Seek.route(front: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, running: running)
        track = nil
        draw(jump: 0)
        if case .script(let player) = route {
            let source = Seek.script(toRead: player)
            scripts.async { [weak self] in
                let reply = Self.run(source)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.track = reply.flatMap(Seek.parse)
                        self.draw(jump: self.hud.model.jump)
                    }
                }
            }
        }
    }

    func preview(_ seconds: Double) { draw(jump: seconds) }

    func commit(_ seconds: Double) {
        hud.hide()
        switch route {
        case .nothing: break
        case .arrows:
            let presses = Seek.arrowPresses(seconds: seconds, arrowSeconds: feel.arrowSeconds)
            scripts.async {
                for _ in 0..<presses.count {
                    Keyboard.press(keyCode: presses.forward ? 124 : 123, flags: 0)
                    usleep(15000)
                }
            }
        case .script(let player):
            guard let track else { return }
            let source = Seek.script(toJump: player, to: Seek.target(position: track.position, duration: track.duration, jump: seconds))
            scripts.async { _ = Self.run(source) }
        }
    }

    func cancel() { hud.hide() }

    private func draw(jump: Double) {
        hud.model.jump = jump
        hud.model.title = track?.title
        hud.model.position = track?.position
        hud.model.duration = track?.duration
        hud.model.nothing = route == .nothing
        if showHUD { hud.show() }
    }

    private nonisolated static func run(_ source: String) -> String? {
        var error: NSDictionary?
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
    }
}

@MainActor @Observable
final class SeekModel {
    var jump = 0.0
    var title: String?
    var position: Double?
    var duration: Double?
    var nothing = false
    var visible = false
}

/// A slim bar near the bottom of the screen. It never takes focus or clicks.
@MainActor
final class SeekHUD {
    let model = SeekModel()
    private var panel: NSPanel?

    func show() {
        let panel = panel ?? make()
        self.panel = panel
        guard let screen = NSScreen.main else { return }
        let size = CGSize(width: 420, height: 74)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 56, width: size.width, height: size.height), display: false)
        panel.orderFrontRegardless()
        withAnimation(Motion.snap) { model.visible = true }
    }

    func hide() {
        withAnimation(.easeOut(duration: 0.18)) { model.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            if !model.visible { panel?.orderOut(nil) }
        }
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: SeekHUDView(model: model).environment(\.colorScheme, .dark))
        return panel
    }
}

struct SeekHUDView: View {
    var model: SeekModel

    private var target: Double? {
        guard let position = model.position, let duration = model.duration else { return nil }
        return Seek.target(position: position, duration: duration, jump: model.jump)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.nothing ? "Nothing to seek here" : Seek.signedClock(model.jump))
                    .font(.system(size: model.nothing ? 14 : 19, weight: .light)).monospacedDigit().foregroundStyle(Theme.ink)
                    .contentTransition(.numericText(value: model.jump))
                    .animation(Motion.snap, value: model.jump)
                if let title = model.title {
                    Text(title).font(.system(size: 12.5, weight: .light)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let target, let duration = model.duration {
                    Text("\(Seek.clock(target)) / \(Seek.clock(duration))").font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.secondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line).frame(height: 3)
                    if let target, let duration = model.duration, duration > 0 {
                        let reach = max(geometry.size.width * target / duration, 3)
                        Capsule().fill(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent], startPoint: .leading, endPoint: .trailing)).frame(width: reach, height: 3)
                        Circle().fill(Theme.ink).frame(width: 7, height: 7).shadow(color: Theme.accent, radius: 7).offset(x: reach - 3.5)
                    } else {
                        // No position to show: how far from where it is now, either way.
                        let middle = geometry.size.width / 2
                        let reach = min(abs(model.jump) / 300, 1) * middle
                        Capsule().fill(Theme.accent).frame(width: max(reach, 3), height: 3).offset(x: model.jump < 0 ? middle - reach : middle)
                        Circle().fill(Theme.ink).frame(width: 7, height: 7).shadow(color: Theme.accent, radius: 7)
                            .offset(x: (model.jump < 0 ? middle - reach : middle + reach) - 3.5)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 8)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(width: 420, height: 74)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.window.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
        .scaleEffect(model.visible ? 1 : 0.94)
        .offset(y: model.visible ? 0 : 12)
        .opacity(model.visible ? 1 : 0)
        .blur(radius: model.visible ? 0 : 4)
    }
}
