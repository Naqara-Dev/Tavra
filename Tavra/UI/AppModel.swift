import AppKit
import ApplicationServices
import Observation
import ServiceManagement
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case trackpad, apps, feel, settings
    var id: String { rawValue }
    var title: String { rawValue == "apps" ? "Apps" : rawValue.capitalized }
    var icon: String {
        switch self {
        case .trackpad: "rectangle.dashed"
        case .apps: "square.grid.2x2"
        case .feel: "slider.horizontal.3"
        case .settings: "gearshape"
        }
    }
}

enum OnboardingStep: String, Sendable {
    case welcome, check, permission, tryIt, done
}

@MainActor @Observable
final class AppModel {
    var page = Page.trackpad
    var selectedZone = Zone.right
    var config: Config {
        didSet {
            guard config != oldValue else { return }
            router.update(config)
            scheduleSave()
        }
    }
    private(set) var isTrusted = false
    private(set) var tapRunning = false
    private(set) var devices: [TouchFeed.Device] = []
    private(set) var frontApp: NSRunningApplication?
    private(set) var lastGesture: String?
    /// Zones that have actually been used since the first-run screen opened.
    private(set) var tried = Set<Zone>()
    private(set) var loginItemEnabled = SMAppService.mainApp.status == .enabled
    var onboardingOpen = false
    var onboardingStep = OnboardingStep.welcome {
        didSet { if onboardingStep == .check { startCheck() } }
    }
    private(set) var check = TrackpadCheck()
    private(set) var checkNeedsHint = false
    var shortcuts: [String] = []
    /// Set by the first view that can open a window.
    @ObservationIgnored var openMainWindow: (() -> Void)?

    @ObservationIgnored let router = GestureRouter()
    @ObservationIgnored private lazy var feed = TouchFeed(router: router)
    @ObservationIgnored private lazy var tap = ClickTap(router: router)
    @ObservationIgnored private var performer: Performing = SystemPerformer()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var checking: Task<Void, Never>?
    @ObservationIgnored private var checkProgress = TrackpadCheck()
    @ObservationIgnored private var isFake = false

    init() {
        config = ConfigStore.load()
        router.update(config)
        router.onEffects = { [weak self] effects in self?.handle(effects) }
        onboardingOpen = !config.onboarded
    }

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        let defaults = UserDefaults.standard
        isFake = defaults.bool(forKey: "TavraFake")
        if isFake { performer = LoggingPerformer() }
        if let raw = defaults.string(forKey: "TavraPage"), let page = Page(rawValue: raw) { self.page = page }
        if let raw = defaults.string(forKey: "TavraZone"), let zone = Zone(rawValue: raw) { selectedZone = zone }
        if let raw = defaults.string(forKey: "TavraStep"), let step = OnboardingStep(rawValue: raw) {
            onboardingOpen = true
            onboardingStep = step
            if step == .check { startCheck() }
        }
        if isFake {
            isTrusted = !defaults.bool(forKey: "TavraUntrusted")
            tapRunning = isTrusted
            devices = [TouchFeed.Device(surface: .builtIn, isBuiltIn: true)]
            print("TAVRA_READY onboarding=\(onboardingOpen)")
            fflush(stdout)
            if defaults.bool(forKey: "TavraDemo") { FakeTouches.run(router: router) }
            if let count = Optional(defaults.integer(forKey: "TavraCheckDemo")), count > 0 { FakeTouches.runCheck(router: router, edges: count) }
            if defaults.bool(forKey: "TavraNoTrackpad") { devices = [] }
        }
        #endif
        applyDockPolicy()
        frontApp = NSWorkspace.shared.frontmostApplication
        router.setFrontApp(frontApp?.bundleIdentifier)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.frontApp = app
                self?.router.setFrontApp(app?.bundleIdentifier)
            }
        })
        // Trackpads stop reporting across a sleep, and nothing may stay held through one.
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.router.reset() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartTouches() }
        })
        guard !isFake else { return }
        restartTouches()
        watch = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkInOnThings()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func quitting() {
        tap.stop()
        router.reset()
        // Whatever state the gesture was in, the pointer goes home with the app.
        if !isFake { CGAssociateMouseAndMouseCursorPosition(1) }
        if !isFake { feed.stop() }
        saveNow()
    }

    private func restartTouches() {
        guard !isFake else { return }
        router.reset()
        feed.start()
        devices = feed.devices
    }

    /// Permission can arrive or be taken away at any time, and trackpads come and go.
    private func checkInOnThings() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        if trusted, !tap.isRunning {
            _ = tap.start()
        } else if !trusted, tap.isRunning {
            tap.stop()
        }
        if tapRunning != tap.isRunning { tapRunning = tap.isRunning }
        if feed.count() != devices.count { restartTouches() }
        if onboardingOpen, onboardingStep == .permission, trusted { onboardingStep = .tryIt }
    }

    // MARK: Gestures

    private func handle(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .began(let zone):
                tried.insert(zone)
                note("BEGAN \(zone.rawValue)")
            case .ended(let zone):
                note("ENDED \(zone.rawValue)")
            case .step(let action, let up, let fine):
                performer.perform(step: action, up: up, fine: fine)
                lastGesture = "\(action.title) \(up ? "up" : "down")"
            case .timelineStarted:
                performer.timelineStarted(hud: config.seekHUD, feel: config.feel)
            case .timelinePreview(let seconds):
                performer.timelinePreview(seconds)
                lastGesture = "Timeline \(Seek.signedClock(seconds))"
            case .timelineCommitted(let seconds):
                performer.timelineCommitted(seconds)
            case .timelineCancelled:
                performer.timelineCancelled()
            case .tap(let action, let zone, let clicks):
                performer.perform(tap: action)
                lastGesture = "\(zone.title), \(clicks) click\(clicks == 1 ? "" : "s"): \(action.title)"
            case .freezePointer(let frozen):
                performer.freezePointer(frozen)
            case .haptic:
                performer.haptic(config.feel.haptics)
            }
        }
    }

    private func note(_ text: String) {
        #if DEBUG
        if isFake {
            print("TAVRA_GESTURE \(text)")
            fflush(stdout)
        }
        #endif
    }

    // MARK: Permission

    func askForAccessibility() {
        guard !isFake else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func finishOnboarding() {
        onboardingOpen = false
        config.onboarded = true
    }

    func resetTried() { tried = [] }

    /// Follows the finger for as long as the check is on screen, and not a moment longer.
    private func startCheck() {
        check = TrackpadCheck()
        checkProgress = TrackpadCheck()
        checkNeedsHint = false
        checking?.cancel()
        checking = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.onboardingOpen, self.onboardingStep == .check else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let state = self.router.snapshot()
                // Its timers change every frame and an @Observable write redraws even when nothing
                // has: the screen only hears about it when an edge is found.
                if self.checkProgress.update(fingers: state.fingers, surface: state.surface, feel: self.config.feel, now: now) {
                    self.performer.haptic(self.config.feel.haptics)
                    self.note("CHECK \(self.checkProgress.found.last?.rawValue ?? "")")
                    self.check = self.checkProgress
                }
                let hint = self.checkProgress.needsHint(now: now)
                if hint != self.checkNeedsHint { self.checkNeedsHint = hint }
                if self.checkProgress.isDone { return }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    // MARK: Apps

    func rule(for bundleID: String) -> AppRule? { config.apps.first { $0.bundleID == bundleID } }

    func addApp(url: URL) {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, rule(for: id) == nil else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        config.apps.append(AppRule(bundleID: id, name: name, path: url.path))
    }

    func addRunning(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier, rule(for: id) == nil, let url = app.bundleURL else { return }
        config.apps.append(AppRule(bundleID: id, name: app.localizedName ?? id, path: url.path))
    }

    func setOff(_ off: Bool, forFrontApp app: NSRunningApplication) {
        guard let id = app.bundleIdentifier else { return }
        if rule(for: id) == nil { addRunning(app) }
        if let index = config.apps.firstIndex(where: { $0.bundleID == id }) { config.apps[index].off = off }
    }

    // MARK: Shortcuts

    /// What's in the Shortcuts app. Read when someone's about to choose one.
    func loadShortcuts() {
        Task.detached(priority: .userInitiated) { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
            await MainActor.run { self?.shortcuts = names }
        }
    }

    // MARK: Outside the app

    func applyDockPolicy() {
        NSApp.setActivationPolicy(config.showInDock ? .regular : .accessory)
    }

    func setLoginItem(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        loginItemEnabled = SMAppService.mainApp.status == .enabled
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        saveTask = nil
        ConfigStore.save(config)
    }
}

#if DEBUG
/// Plays a finger and its clicks into the router, so everything above it runs without a trackpad and
/// without touching a single real click. `-TavraFake YES -TavraDemo YES`.
enum FakeTouches {
    /// Touches the edges in turn, holding each long enough to count, and leaves a finger on the last.
    static func runCheck(router: GestureRouter, edges: Int) {
        Task.detached {
            let surface = Surface.builtIn
            let points: [(Double, Double)] = [(120, 38), (5, 38), (62, 5), (62, 72)]
            try? await Task.sleep(for: .seconds(1))
            for (index, point) in points.prefix(edges).enumerated() {
                for _ in 0..<12 {
                    router.touches([Finger(id: 1, x: point.0 / surface.widthMM, y: point.1 / surface.heightMM)], surface: surface)
                    try? await Task.sleep(for: .milliseconds(30))
                }
                if index + 1 < edges {
                    router.touches([], surface: surface)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
    }

    static func run(router: GestureRouter) {
        Task.detached {
            let surface = Surface.builtIn
            func touch(_ x: Double, _ y: Double, id: Int64 = 1) { router.touches([Finger(id: id, x: x / surface.widthMM, y: y / surface.heightMM)], surface: surface) }
            func lift() { router.touches([], surface: surface) }
            func pause(_ ms: Int = 40) async { try? await Task.sleep(for: .milliseconds(ms)) }
            try? await Task.sleep(for: .seconds(1))

            // An ordinary click in the middle.
            touch(60, 38); await pause()
            print("TAVRA_CLICK middle \(router.mouseDown(flags: 0) ? "taken" : "passed")")
            print("TAVRA_CLICK middle-up \(router.mouseUp() ? "taken" : "passed")")
            lift(); await pause()

            // Volume up, then down a little.
            touch(120, 15); await pause()
            print("TAVRA_CLICK right \(router.mouseDown(flags: 0) ? "taken" : "passed")")
            for y in stride(from: 15.0, through: 40, by: 2) {
                touch(120, y)
                await pause(30)
            }
            touch(120, 34); await pause()
            _ = router.mouseUp(); lift(); await pause()

            // A jump on the timeline.
            touch(30, 5); await pause()
            _ = router.mouseDown(flags: 0)
            for x in stride(from: 30.0, through: 55, by: 2.5) {
                touch(x, 5)
                await pause(30)
            }
            _ = router.mouseUp(); lift(); await pause()

            // A corner.
            touch(120, 74); await pause()
            _ = router.mouseDown(flags: 0)
            _ = router.mouseUp(); lift()
            try? await Task.sleep(for: .milliseconds(500))
            fflush(stdout)

            // A finger left on the edge, for looking at.
            touch(119, 40)
            print("TAVRA_DEMO done")
            fflush(stdout)
        }
    }
}
#endif
