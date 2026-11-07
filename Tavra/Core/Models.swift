import Foundation

/// A part of the trackpad that can be given a job.
enum Zone: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }
    var isCorner: Bool { self == .topLeft || self == .topRight || self == .bottomLeft || self == .bottomRight }

    var title: String {
        switch self {
        case .left: "Left edge"
        case .right: "Right edge"
        case .top: "Top edge"
        case .bottom: "Bottom edge"
        case .topLeft: "Top left corner"
        case .topRight: "Top right corner"
        case .bottomLeft: "Bottom left corner"
        case .bottomRight: "Bottom right corner"
        }
    }

    static let edges: [Zone] = [.left, .right, .top, .bottom]
    static let corners: [Zone] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

/// A key press, with what it looks like: "⇧⌘4".
struct KeyCombo: Codable, Hashable, Sendable {
    var keyCode: UInt16
    /// CGEventFlags, raw.
    var flags: UInt64
    var label: String

    init(_ keyCode: UInt16, _ flags: UInt64 = 0, _ label: String) {
        self.keyCode = keyCode
        self.flags = flags
        self.label = label
    }
}

/// CGEventFlags, spelled out so the logic doesn't need CoreGraphics.
enum Flag {
    static let shift: UInt64 = 0x20000
    static let control: UInt64 = 0x40000
    static let option: UInt64 = 0x80000
    static let command: UInt64 = 0x100000
}

/// What sliding along an edge does.
enum SlideAction: Codable, Hashable, Sendable {
    case none
    case volume
    case brightness
    case keyboardBrightness
    case timeline
    /// A key for each step in either direction: next and previous tab, zoom in and out.
    case keys(up: KeyCombo, down: KeyCombo, name: String)

    var title: String {
        switch self {
        case .none: "Nothing"
        case .volume: "Volume"
        case .brightness: "Brightness"
        case .keyboardBrightness: "Keyboard light"
        case .timeline: "Media timeline"
        case .keys(_, _, let name): name
        }
    }

    var icon: String {
        switch self {
        case .none: "minus"
        case .volume: "speaker.wave.2"
        case .brightness: "sun.max"
        case .keyboardBrightness: "light.max"
        case .timeline: "play.square"
        case .keys: "keyboard"
        }
    }

    static let presets: [SlideAction] = [
        .keys(up: KeyCombo(48, Flag.control, "⌃⇥"), down: KeyCombo(48, Flag.control | Flag.shift, "⌃⇧⇥"), name: "Browser tabs"),
        .keys(up: KeyCombo(24, Flag.command, "⌘="), down: KeyCombo(27, Flag.command, "⌘−"), name: "Zoom"),
        .keys(up: KeyCombo(6, Flag.command | Flag.shift, "⇧⌘Z"), down: KeyCombo(6, Flag.command, "⌘Z"), name: "Undo and redo"),
        .keys(up: KeyCombo(124, Flag.control, "⌃→"), down: KeyCombo(123, Flag.control, "⌃←"), name: "Desktops"),
    ]
}

/// What clicking a corner does.
enum TapAction: Codable, Hashable, Sendable {
    case none
    case mute
    case playPause
    case nextTrack
    case previousTrack
    case keys(KeyCombo, name: String)
    case openApp(path: String, name: String)
    case openURL(String, browser: String?)
    case openPath(String)
    case shortcut(String)

    var title: String {
        switch self {
        case .none: "Nothing"
        case .mute: "Mute"
        case .playPause: "Play or pause"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .keys(let combo, let name): name.isEmpty ? combo.label : name
        case .openApp(_, let name): "Open \(name)"
        case .openURL(let url, _): url.replacingOccurrences(of: "https://", with: "")
        case .openPath(let path): (path as NSString).lastPathComponent
        case .shortcut(let name): name
        }
    }

    var icon: String {
        switch self {
        case .none: "minus"
        case .mute: "speaker.slash"
        case .playPause: "playpause"
        case .nextTrack: "forward"
        case .previousTrack: "backward"
        case .keys: "keyboard"
        case .openApp: "app"
        case .openURL: "link"
        case .openPath: "folder"
        case .shortcut: "square.stack.3d.up"
        }
    }

    static let presets: [TapAction] = [
        .keys(KeyCombo(21, Flag.command | Flag.shift, "⇧⌘4"), name: "Screenshot"),
        .keys(KeyCombo(126, Flag.control, "⌃↑"), name: "Mission Control"),
        .keys(KeyCombo(125, Flag.control, "⌃↓"), name: "App windows"),
        .keys(KeyCombo(12, Flag.control | Flag.command, "⌃⌘Q"), name: "Lock screen"),
        .keys(KeyCombo(49, Flag.command, "⌘Space"), name: "Spotlight"),
    ]
}

/// Who does what. A set of these can also be partial: an app's own changes, on top of the defaults.
struct Bindings: Codable, Hashable, Sendable {
    var slides: [String: SlideAction] = [:]
    /// Zone, then number of clicks.
    var taps: [String: [String: TapAction]] = [:]

    func slide(_ zone: Zone) -> SlideAction { slides[zone.rawValue] ?? .none }

    func tap(_ zone: Zone, clicks: Int) -> TapAction { taps[zone.rawValue]?[String(clicks)] ?? .none }

    /// Click counts this corner answers to.
    func clickCounts(_ zone: Zone) -> [Int] {
        (taps[zone.rawValue] ?? [:]).filter { $0.value != .none }.keys.compactMap(Int.init).sorted()
    }

    func has(_ zone: Zone) -> Bool {
        zone.isCorner ? !clickCounts(zone).isEmpty : slide(zone) != .none
    }

    mutating func setTap(_ action: TapAction?, zone: Zone, clicks: Int) {
        var map = taps[zone.rawValue] ?? [:]
        map[String(clicks)] = action
        taps[zone.rawValue] = map.isEmpty ? nil : map
    }

    /// These, with an app's changes on top. `.none` in the app's set switches a zone off for that app.
    func merged(with other: Bindings) -> Bindings {
        var result = self
        for (zone, action) in other.slides { result.slides[zone] = action }
        // An app that changes a corner at all takes over that whole corner, so clicks can't get mixed up.
        for (zone, map) in other.taps { result.taps[zone] = map }
        return result
    }

    static let starter = Bindings(
        slides: [Zone.right.rawValue: .volume, Zone.left.rawValue: .brightness, Zone.bottom.rawValue: .timeline],
        taps: [Zone.topRight.rawValue: ["1": .playPause, "2": .nextTrack]])
}

/// Something an app does differently.
struct AppRule: Codable, Hashable, Identifiable, Sendable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var path: String
    /// Tavra leaves this app alone entirely.
    var off = false
    var bindings = Bindings()
}

enum ModifierChoice: String, Codable, CaseIterable, Sendable {
    case none, option, control, command, shift

    var title: String {
        switch self {
        case .none: "None"
        case .option: "⌥"
        case .control: "⌃"
        case .command: "⌘"
        case .shift: "⇧"
        }
    }

    var flag: UInt64 {
        switch self {
        case .none: 0
        case .option: Flag.option
        case .control: Flag.control
        case .command: Flag.command
        case .shift: Flag.shift
        }
    }
}

enum HapticChoice: String, Codable, CaseIterable, Sendable {
    case off, light, medium, firm
    var title: String { rawValue.capitalized }
}

enum AppearanceChoice: String, Codable, CaseIterable, Sendable {
    case dark, light, system
    var title: String { rawValue.capitalized }
}

/// How gestures feel. All in millimetres, so a slide feels the same on a bigger trackpad.
struct FeelSettings: Codable, Hashable, Sendable {
    var edgeMM = 12.0
    var cornerMM = 22.0
    /// How far a finger travels for one step.
    var stepMM = 4.0
    /// How much of the side edges counts, from the bottom up. 1 is all of it.
    var sideSpan = 1.0
    var invert = false
    var requiredModifier = ModifierChoice.none
    var freezePointer = true
    var haptics = HapticChoice.medium
    /// Seconds a slide across the whole trackpad covers on a media timeline.
    var timelineSeconds = 300.0
    /// Seconds one arrow key jumps, in players Tavra can't ask.
    var arrowSeconds = 5.0
    /// How long a corner waits to see if another click is coming.
    var multiClickSeconds = 0.3

    init() {}

    /// A setting added in a later version takes its default when an older file doesn't have it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = FeelSettings()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T { try c.decodeIfPresent(T.self, forKey: key) ?? fallback }
        edgeMM = try get(.edgeMM, d.edgeMM)
        cornerMM = try get(.cornerMM, d.cornerMM)
        stepMM = try get(.stepMM, d.stepMM)
        sideSpan = try get(.sideSpan, d.sideSpan)
        invert = try get(.invert, d.invert)
        requiredModifier = try get(.requiredModifier, d.requiredModifier)
        freezePointer = try get(.freezePointer, d.freezePointer)
        haptics = try get(.haptics, d.haptics)
        timelineSeconds = try get(.timelineSeconds, d.timelineSeconds)
        arrowSeconds = try get(.arrowSeconds, d.arrowSeconds)
        multiClickSeconds = try get(.multiClickSeconds, d.multiClickSeconds)
    }
}

struct Config: Codable, Hashable, Sendable {
    var bindings = Bindings.starter
    var apps: [AppRule] = []
    var feel = FeelSettings()
    var paused = false
    var onboarded = false
    var showInMenuBar = true
    var showInDock = false
    var seekHUD = true
    var appearance = AppearanceChoice.dark

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T { try c.decodeIfPresent(T.self, forKey: key) ?? fallback }
        bindings = try get(.bindings, d.bindings)
        apps = try get(.apps, d.apps)
        feel = try get(.feel, d.feel)
        paused = try get(.paused, d.paused)
        onboarded = try get(.onboarded, d.onboarded)
        showInMenuBar = try get(.showInMenuBar, d.showInMenuBar)
        showInDock = try get(.showInDock, d.showInDock)
        seekHUD = try get(.seekHUD, d.seekHUD)
        appearance = try get(.appearance, d.appearance)
    }

    /// What's in force with this app in front. nil means Tavra keeps out of the way.
    func bindings(forApp bundleID: String?) -> Bindings? {
        if paused { return nil }
        guard let bundleID, let rule = apps.first(where: { $0.bundleID == bundleID }) else { return bindings }
        return rule.off ? nil : bindings.merged(with: rule.bindings)
    }
}

enum ConfigStore {
    static var home: URL {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["TAVRA_HOME"] { return URL(fileURLWithPath: path, isDirectory: true) }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Tavra", directoryHint: .isDirectory)
    }

    static var file: URL { home.appending(path: "config.json") }

    static func load() -> Config {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
    }

    @discardableResult
    static func save(_ config: Config) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return false }
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return (try? data.write(to: file, options: .atomic)) != nil
    }
}
