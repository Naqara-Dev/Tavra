import AppKit
import SwiftUI

/// Gives one zone its job. `base` is set when editing an app's changes on top of the defaults, and then
/// every choice can also be "the same as everywhere else".
struct ZoneEditor: View {
    var model: AppModel
    var zone: Zone
    @Binding var bindings: Bindings
    var base: Bindings?

    @State private var clicks = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(zone.title).font(.system(size: 19, weight: .light)).tracking(-0.3).foregroundStyle(Theme.ink)
                Text(zone.isCorner ? "Press until it clicks. One to four clicks can each do something different." : "Press until it clicks, then slide. Let go when you're done.")
                    .font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if zone.isCorner { cornerEditor } else { slideEditor }
        }
        .onChange(of: zone) { clicks = 1 }
    }

    // MARK: Edges

    private var currentSlide: SlideAction? { bindings.slides[zone.rawValue] }

    @ViewBuilder private var slideEditor: some View {
        let shown = currentSlide ?? base?.slide(zone) ?? .none
        Dropdown(icon: shown.icon, title: base != nil && currentSlide == nil ? "Default: \(shown.title)" : shown.title, height: 34) { slideEntries() }
        if case .keys(let up, let down, let name) = currentSlide, !SlideAction.presets.contains(where: { $0.title == name }) {
            VStack(alignment: .leading, spacing: 10) {
                KeyRow(title: zone == .left || zone == .right ? "Sliding up" : "Sliding right", combo: up) { combo in
                    setSlide(.keys(up: combo, down: down, name: name))
                }
                KeyRow(title: zone == .left || zone == .right ? "Sliding down" : "Sliding left", combo: down) { combo in
                    setSlide(.keys(up: up, down: combo, name: name))
                }
            }
        }
        if shown == .timeline { timelineNote }
    }

    private func setSlide(_ action: SlideAction?) {
        bindings.slides[zone.rawValue] = action
    }

    private func slideEntries() -> [DropdownEntry] {
        var entries: [DropdownEntry] = []
        if base != nil {
            entries.append(.item("Default", detail: "The same as everywhere else", isOn: currentSlide == nil, id: "same") { setSlide(nil) })
            entries.append(.divider("same"))
        }
        let setting: SlideAction? = base == nil ? (currentSlide ?? SlideAction.none) : currentSlide
        for action in [SlideAction.none, .volume, .brightness, .keyboardBrightness, .timeline] {
            entries.append(.item(action.title, icon: action.icon, isOn: setting == action, id: action.title) { setSlide(action) })
        }
        entries.append(.divider("presets"))
        entries.append(.heading("One key per step"))
        for action in SlideAction.presets {
            entries.append(.item(action.title, icon: action.icon, isOn: setting == action, id: action.title) { setSlide(action) })
        }
        let isCustom: Bool = {
            if case .keys(_, _, let name) = setting { return !SlideAction.presets.contains { $0.title == name } }
            return false
        }()
        entries.append(.item("Your own keys…", icon: "keyboard", isOn: isCustom, id: "custom") {
            setSlide(.keys(up: KeyCombo(126, 0, "↑"), down: KeyCombo(125, 0, "↓"), name: "Your keys"))
        })
        return entries
    }

    private var timelineNote: some View {
        Text("Music and Spotify jump to the exact second. Browsers and video players get arrow keys, which is as precise as the player makes them. Sliding off the edge cancels.")
            .font(.system(size: 11.5, weight: .light)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Corners

    private var ownsCorner: Bool { bindings.taps[zone.rawValue] != nil }
    private var effective: Bindings { base.map { $0.merged(with: bindings) } ?? bindings }

    @ViewBuilder private var cornerEditor: some View {
        Segments(options: [1, 2, 3, 4], selection: $clicks) { "\($0)×" }
        let shown = effective.tap(zone, clicks: clicks)
        Dropdown(icon: shown.icon, title: base != nil && !ownsCorner ? "Default: \(shown.title)" : shown.title, height: 34) { tapEntries(current: shown) }
        tapDetail(shown)
        let others = effective.clickCounts(zone).filter { $0 != clicks }
        if !others.isEmpty {
            Text("Also set on \(others.map { "\($0)×" }.joined(separator: ", ")).")
                .font(.system(size: 11.5, weight: .light)).foregroundStyle(Theme.tertiary)
        }
    }

    /// An app's first change to a corner starts from what the corner does everywhere else.
    private func setTap(_ action: TapAction?) {
        if let base, !ownsCorner { bindings.taps[zone.rawValue] = base.taps[zone.rawValue] ?? [:] }
        bindings.setTap(action == TapAction.none && base == nil ? nil : action, zone: zone, clicks: clicks)
        if base != nil, bindings.taps[zone.rawValue] == nil { bindings.taps[zone.rawValue] = [:] }
    }

    private func tapEntries(current: TapAction) -> [DropdownEntry] {
        var entries: [DropdownEntry] = []
        if base != nil {
            entries.append(.item("Default", detail: "The same as everywhere else", isOn: !ownsCorner, id: "same") { bindings.taps[zone.rawValue] = nil })
            entries.append(.divider("same"))
        }
        for action in [TapAction.none, .mute, .playPause, .nextTrack, .previousTrack] {
            entries.append(.item(action.title, icon: action.icon, isOn: current == action, id: action.title) { setTap(action) })
        }
        entries.append(.divider("presets"))
        for action in TapAction.presets {
            entries.append(.item(action.title, icon: action.icon, isOn: current == action, id: action.title) { setTap(action) })
        }
        entries.append(.divider("more"))
        entries.append(.item("Open an app…", icon: "app", id: "open-app") { chooseApp() })
        entries.append(.item("Open a link…", icon: "link", id: "open-link") { setTap(.openURL("https://", browser: nil)) })
        entries.append(.item("Open a file or folder…", icon: "folder", id: "open-path") { choosePath() })
        entries.append(.item("Press your own keys…", icon: "keyboard", id: "keys") { setTap(.keys(KeyCombo(36, 0, "↩"), name: "")) })
        entries.append(.item("Run a Shortcut…", icon: "square.stack.3d.up", id: "shortcut") {
            model.loadShortcuts()
            setTap(.shortcut(""))
        })
        return entries
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setTap(.openApp(path: url.path, name: url.deletingPathExtension().lastPathComponent))
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setTap(.openPath(url.path))
    }

    @ViewBuilder private func tapDetail(_ action: TapAction) -> some View {
        switch action {
        case .openURL(let url, let browser):
            SoftField("Address", text: Binding(get: { url }, set: { setTap(.openURL($0, browser: browser)) }))
            Dropdown(icon: "globe", title: browser.map { FileManager.default.displayName(atPath: $0).replacingOccurrences(of: ".app", with: "") } ?? "Default browser", height: 34) {
                var entries: [DropdownEntry] = [.item("Default browser", isOn: browser == nil, id: "default") { setTap(.openURL(url, browser: nil)) }]
                if let web = URL(string: "https://example.com") {
                    for app in NSWorkspace.shared.urlsForApplications(toOpen: web) {
                        entries.append(.item(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: ""), isOn: browser == app.path, id: app.path) {
                            setTap(.openURL(url, browser: app.path))
                        })
                    }
                }
                return entries
            }
        case .keys(let combo, let name) where !TapAction.presets.contains(action):
            KeyRow(title: "Press", combo: combo) { setTap(.keys($0, name: name)) }
        case .shortcut(let name):
            Dropdown(icon: "square.stack.3d.up", title: name.isEmpty ? "Choose a Shortcut" : name, placeholder: name.isEmpty, height: 34) {
                model.shortcuts.isEmpty
                    ? [.heading("None found in the Shortcuts app")]
                    : model.shortcuts.map { shortcut in .item(shortcut, isOn: shortcut == name, id: "shortcut:\(shortcut)") { setTap(.shortcut(shortcut)) } }
            }
            .onAppear { model.loadShortcuts() }
        case .openApp:
            Text("Click again with it in front to hide it.").font(.system(size: 11.5, weight: .light)).foregroundStyle(Theme.tertiary)
        default:
            EmptyView()
        }
    }
}

/// A label, and a button that records the next key pressed.
struct KeyRow: View {
    var title: String
    var combo: KeyCombo
    var change: (KeyCombo) -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            Spacer()
            Button(recording ? "Press keys…" : combo.label) { recording ? stop() : start() }
                .buttonStyle(QuietButtonStyle(tint: recording ? Theme.accent : Theme.ink))
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape stops listening, unless a modifier makes it a combination of its own.
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop()
                return nil
            }
            change(KeyNames.combo(from: event))
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

enum KeyNames {
    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌅", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func combo(from event: NSEvent) -> KeyCombo {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var flags: UInt64 = 0
        var label = ""
        if modifiers.contains(.control) { flags |= Flag.control; label += "⌃" }
        if modifiers.contains(.option) { flags |= Flag.option; label += "⌥" }
        if modifiers.contains(.shift) { flags |= Flag.shift; label += "⇧" }
        if modifiers.contains(.command) { flags |= Flag.command; label += "⌘" }
        label += special[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "?").uppercased()
        return KeyCombo(event.keyCode, flags, label)
    }
}
