import AppKit
import CoreGraphics
import Foundation

/// Carries out what a gesture asked for.
@MainActor
protocol Performing: AnyObject {
    func perform(step action: SlideAction, up: Bool, fine: Bool)
    func perform(tap action: TapAction)
    func haptic(_ choice: HapticChoice)
    func freezePointer(_ frozen: Bool)
    func timelineStarted(hud: Bool, feel: FeelSettings)
    func timelinePreview(_ seconds: Double)
    func timelineCommitted(_ seconds: Double)
    func timelineCancelled()
}

/// The real thing. Volume and brightness press the same keys the keyboard does, which brings the
/// system's own indicator and its exact steps along.
@MainActor
final class SystemPerformer: Performing {
    private let seeker = MediaSeeker()
    private var frozenAt: CGPoint?

    // NX_KEYTYPE values from IOKit's ev_keymap.h.
    private enum SystemKey: Int32 {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
        case play = 16, next = 17, previous = 18, lightUp = 21, lightDown = 22
    }

    private func press(_ key: SystemKey, fine: Bool = false) {
        let extra: NSEvent.ModifierFlags = fine ? [.shift, .option] : []
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)).union(extra),
                                           timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                                           data1: Int(key.rawValue) << 16 | state << 8, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private func press(_ combo: KeyCombo) {
        Keyboard.press(keyCode: combo.keyCode, flags: combo.flags)
    }

    func perform(step action: SlideAction, up: Bool, fine: Bool) {
        switch action {
        case .none, .timeline: break
        case .volume: press(up ? .soundUp : .soundDown, fine: fine)
        case .brightness: press(up ? .brightnessUp : .brightnessDown, fine: fine)
        case .keyboardBrightness: press(up ? .lightUp : .lightDown, fine: fine)
        case .keys(let upKey, let downKey, _): press(up ? upKey : downKey)
        }
    }

    func perform(tap action: TapAction) {
        switch action {
        case .none: break
        case .mute: press(.mute)
        case .playPause: press(.play)
        case .nextTrack: press(.next)
        case .previousTrack: press(.previous)
        case .keys(let combo, _): press(combo)
        case .openApp(let path, _): openApp(path)
        case .openURL(let text, let browser): open(text, browser: browser)
        case .openPath(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .shortcut(let name): runShortcut(name)
        }
    }

    /// Click again with it in front to tuck it away.
    private func openApp(_ path: String) {
        let url = URL(fileURLWithPath: path)
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleURL == url {
            front.hide()
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func open(_ text: String, browser: String?) {
        guard let url = URL(string: text.contains("://") ? text : "https://\(text)") else { return }
        if let browser {
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: browser), configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func runShortcut(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    func haptic(_ choice: HapticChoice) {
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch choice {
        case .off: return
        case .light: pattern = .alignment
        case .medium: pattern = .levelChange
        case .firm: pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func freezePointer(_ frozen: Bool) {
        if frozen {
            frozenAt = CGEvent(source: nil)?.location
            CGAssociateMouseAndMouseCursorPosition(0)
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            if let frozenAt { CGWarpMouseCursorPosition(frozenAt) }
            // A warp can leave the pointer stuck for a moment unless it's told to follow again.
            CGAssociateMouseAndMouseCursorPosition(1)
            frozenAt = nil
        }
    }

    func timelineStarted(hud: Bool, feel: FeelSettings) { seeker.start(showHUD: hud, feel: feel) }
    func timelinePreview(_ seconds: Double) { seeker.preview(seconds) }
    func timelineCommitted(_ seconds: Double) { seeker.commit(seconds) }
    func timelineCancelled() { seeker.cancel() }
}

enum Keyboard {
    /// Key-down and key-up, with these modifiers held.
    static func press(keyCode: UInt16, flags: UInt64) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
            event?.flags = CGEventFlags(rawValue: flags)
            event?.post(tap: .cghidEventTap)
        }
    }
}

#if DEBUG
/// For tests: says what it would have done, and does none of it.
@MainActor
final class LoggingPerformer: Performing {
    private func note(_ text: String) {
        print("TAVRA_DO \(text)")
        fflush(stdout)
    }

    func perform(step action: SlideAction, up: Bool, fine: Bool) { note("step \(action.title) \(up ? "up" : "down")\(fine ? " fine" : "")") }
    func perform(tap action: TapAction) { note("tap \(action.title)") }
    func haptic(_ choice: HapticChoice) {}
    func freezePointer(_ frozen: Bool) { note("pointer \(frozen ? "held" : "free")") }
    func timelineStarted(hud: Bool, feel: FeelSettings) { note("timeline start") }
    func timelinePreview(_ seconds: Double) {}
    func timelineCommitted(_ seconds: Double) { note("timeline jump \(Int(seconds.rounded()))") }
    func timelineCancelled() { note("timeline cancel") }
}
#endif
