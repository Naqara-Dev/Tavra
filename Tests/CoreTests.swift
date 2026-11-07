import Foundation

nonisolated(unsafe) var passed = 0
nonisolated(unsafe) var failures: [String] = []

func check(_ condition: @autoclosure () -> Bool, _ what: String) {
    if condition() { passed += 1 } else { failures.append(what) }
}

/// Fixed here, so changing what ships doesn't change what's being tested.
private let plain = Bindings(slides: [Zone.right.rawValue: .volume, Zone.left.rawValue: .brightness, Zone.bottom.rawValue: .timeline],
                             taps: [Zone.topLeft.rawValue: ["1": .mute]])

/// A trackpad under test: says where a finger is in millimetres from the left and bottom.
private struct Pad {
    var engine = GestureEngine()
    var now: TimeInterval = 100
    var surface = Surface.builtIn

    mutating func finger(_ x: Double, _ y: Double, id: Int64 = 1) -> [Effect] {
        now += 0.01
        return engine.touches([Finger(id: id, x: x / surface.widthMM, y: y / surface.heightMM)], surface: surface, now: now)
    }

    mutating func fingers(_ points: [(Double, Double)]) -> [Effect] {
        now += 0.01
        return engine.touches(points.enumerated().map { Finger(id: Int64($0.offset + 1), x: $0.element.0 / surface.widthMM, y: $0.element.1 / surface.heightMM) }, surface: surface, now: now)
    }

    mutating func lift() -> [Effect] {
        now += 0.01
        return engine.touches([], surface: surface, now: now)
    }

    mutating func down(flags: UInt64 = 0, bindings: Bindings? = plain) -> (swallow: Bool, effects: [Effect]) {
        now += 0.01
        return engine.mouseDown(flags: flags, bindings: bindings, now: now)
    }

    mutating func up() -> (swallow: Bool, effects: [Effect]) {
        now += 0.01
        return engine.mouseUp(now: now)
    }
}

private let right = 120.0, left = 5.0, middleY = 38.0, middleX = 62.0

func testOrdinaryClicks() {
    var pad = Pad()
    _ = pad.finger(middleX, middleY)
    var click = pad.down()
    check(!click.swallow && click.effects.isEmpty, "a click in the middle goes straight through")
    check(!pad.up().swallow, "and so does its release")

    pad = Pad()
    click = pad.down()
    check(!click.swallow, "a click with no finger on the trackpad is a mouse: it goes through")
    _ = pad.up()

    pad = Pad()
    _ = pad.finger(right, middleY)
    _ = pad.lift()
    check(!pad.down().swallow, "tap-to-click has lifted already: it goes through")

    pad = Pad()
    _ = pad.fingers([(right, middleY), (middleX, 10)])
    check(!pad.down().swallow, "two fingers, a palm say, start nothing")

    pad = Pad()
    _ = pad.finger(middleX, middleY)
    _ = pad.finger(right, middleY)
    check(!pad.down().swallow, "a finger that slid into the edge didn't land there: nothing")
    _ = pad.up()

    pad = Pad()
    _ = pad.finger(right, middleY)
    _ = pad.finger(middleX, middleY)
    check(!pad.down().swallow, "a finger that landed on the edge and moved off: nothing")

    pad = Pad()
    _ = pad.finger(right, middleY)
    check(!pad.down(bindings: nil).swallow, "paused, or off in this app: nothing")

    pad = Pad()
    _ = pad.finger(right, middleY)
    check(!pad.down(flags: Flag.command).swallow, "⌘ keeps an edge click ordinary")
    pad = Pad()
    _ = pad.finger(right, middleY)
    check(!pad.down(flags: Flag.control).swallow, "and so does ⌃")

    pad = Pad()
    _ = pad.finger(middleX, 74)
    check(!pad.down().swallow, "an edge with no job is an ordinary part of the trackpad")
    pad = Pad()
    _ = pad.finger(110, 74)
    check(!pad.down().swallow, "and so is a corner with no job")
}

func testSliding() {
    var pad = Pad()
    _ = pad.finger(right, 20)
    let click = pad.down()
    check(click.swallow, "a click on the edge is taken")
    check(click.effects == [.began(.right), .freezePointer(true)], "and holds the pointer still")
    check(pad.engine.mouseDragged(flags: 0, now: pad.now), "its drags are taken too")

    var effects = pad.finger(right, 20 + 3.9)
    check(effects.isEmpty, "under one step does nothing")
    effects = pad.finger(right, 20 + 4.1)
    check(effects == [.step(.volume, up: true, fine: false), .haptic], "one step up, and a tick under the finger")
    effects = pad.finger(right, 20 + 12.1)
    check(effects.filter { if case .step = $0 { true } else { false } }.count == 2, "a fast move doesn't lose steps")
    effects = pad.finger(right, 20 - 4.1)
    let downs = effects.filter { $0 == .step(.volume, up: false, fine: false) }.count
    check(downs == 4, "and back down through zero")
    let release = pad.up()
    check(release.swallow, "its release is taken")
    check(release.effects == [.freezePointer(false), .ended(.right)], "and the pointer comes back")
    check(!pad.engine.isBusy, "and it's over")
    check(!pad.down(bindings: nil).swallow, "the next click is ordinary again")
    _ = pad.up()

    pad = Pad()
    _ = pad.finger(left, 20)
    _ = pad.down()
    effects = pad.finger(left, 24.1)
    check(effects.first == .step(.brightness, up: true, fine: false), "the left edge is brightness")

    pad = Pad()
    pad.engine.feel.invert = true
    _ = pad.finger(right, 20)
    _ = pad.down()
    check(pad.finger(right, 24.1).first == .step(.volume, up: false, fine: false), "direction can be flipped")

    pad = Pad()
    _ = pad.finger(right, 20)
    _ = pad.down(flags: GestureEngine.fineFlags)
    check(pad.finger(right, 24.1).first == .step(.volume, up: true, fine: true), "⇧⌥ gives quarter steps")

    pad = Pad()
    pad.engine.feel.stepMM = 8
    _ = pad.finger(right, 20)
    _ = pad.down()
    check(pad.finger(right, 24.1).isEmpty, "a longer step takes further")

    pad = Pad()
    pad.engine.feel.freezePointer = false
    _ = pad.finger(right, 20)
    check(pad.down().effects == [.began(.right)], "the pointer can be left free")

    // Leaving the strip.
    pad = Pad()
    _ = pad.finger(right, 20)
    _ = pad.down()
    check(pad.finger(124.8 - 15, 20).isEmpty, "a little past the strip is forgiven")
    effects = pad.finger(middleX, 20)
    check(effects == [.freezePointer(false), .ended(.right)], "well past it, the gesture ends and the pointer is free")
    check(pad.engine.mouseDragged(flags: 0, now: pad.now), "the rest of that click stays out of apps")
    check(pad.up().swallow, "including its release")
    check(!pad.engine.isBusy, "then it's over")

    // A second finger landing mid-slide changes nothing.
    pad = Pad()
    _ = pad.finger(right, 20)
    _ = pad.down()
    now_second: do {
        let effects = pad.fingers([(right, 24.1), (middleX, 10)])
        check(effects.first == .step(.volume, up: true, fine: false), "a second finger mid-slide is ignored")
    }

    // Other kinds of slide.
    var bindings = Bindings()
    bindings.slides[Zone.top.rawValue] = SlideAction.presets[0]
    pad = Pad()
    _ = pad.finger(30, 74)
    check(pad.down(bindings: bindings).swallow, "any edge can have a job")
    if case .step(.keys(_, _, let name), let up, _) = pad.finger(34.1, 74).first {
        check(name == "Browser tabs" && up, "keys, one per step, left to right along the top")
    } else {
        check(false, "a key slide steps")
    }
}

func testTimeline() {
    var pad = Pad()
    _ = pad.finger(30, 5)
    let click = pad.down()
    check(click.effects == [.began(.bottom), .freezePointer(true), .timelineStarted], "the bottom edge starts a seek")
    var effects = pad.finger(30 + pad.surface.widthMM / 5, 5)
    guard case .timelinePreview(let seconds)? = effects.first else { return check(false, "sliding previews") }
    check(abs(seconds - 60) < 0.01, "a fifth of the trackpad is a fifth of five minutes")
    check(!effects.contains { if case .step = $0 { true } else { false } }, "nothing happens to the media yet")
    let release = pad.up()
    check(release.effects.first == .timelineCommitted(seconds), "letting go jumps there")

    pad = Pad()
    _ = pad.finger(100, 5)
    _ = pad.down()
    effects = pad.finger(100 - pad.surface.widthMM / 10, 5)
    if case .timelinePreview(let back)? = effects.first { check(abs(back + 30) < 0.01, "sliding left goes back") } else { check(false, "back previews") }

    pad = Pad()
    _ = pad.finger(30, 5)
    _ = pad.down()
    _ = pad.finger(60, 5)
    effects = pad.finger(60, 40)
    check(effects.first == .timelineCancelled, "leaving the strip cancels the jump")
    check(pad.up().effects.isEmpty, "and letting go after that does nothing")

    pad = Pad()
    _ = pad.finger(30, 5)
    _ = pad.down()
    check(pad.up().effects.first == .timelineCancelled, "a click with no slide jumps nowhere")

    pad = Pad()
    pad.engine.feel.timelineSeconds = 600
    _ = pad.finger(30, 5)
    _ = pad.down()
    if case .timelinePreview(let long)? = pad.finger(30 + pad.surface.widthMM / 5, 5).first {
        check(abs(long - 120) < 0.01, "how much a slide covers can be changed")
    } else {
        check(false, "a longer span previews")
    }
}

func testCorners() {
    var bindings = plain
    var pad = Pad()
    _ = pad.finger(5, 74)
    let down = pad.down(bindings: bindings)
    check(down.swallow && down.effects == [.began(.topLeft)], "a corner with a job is taken, and the pointer isn't held")
    let up = pad.up()
    check(up.swallow, "so is its release")
    check(up.effects.contains(.tap(.mute, zone: .topLeft, clicks: 1)), "with one action it fires at once, no waiting")
    check(!pad.engine.isBusy, "and it's over")

    // Several click counts: wait to see.
    bindings.setTap(.playPause, zone: .topLeft, clicks: 2)
    bindings.setTap(.nextTrack, zone: .topLeft, clicks: 4)
    pad = Pad()
    _ = pad.finger(5, 74)
    _ = pad.down(bindings: bindings)
    check(pad.up().effects.isEmpty, "with more possible, it waits")
    check(pad.engine.tick(now: pad.now + 0.1).isEmpty, "not yet")
    check(pad.engine.tick(now: pad.now + 0.31).contains(.tap(.mute, zone: .topLeft, clicks: 1)), "then one click means one click")

    pad = Pad()
    _ = pad.finger(5, 74)
    _ = pad.down(bindings: bindings)
    _ = pad.up()
    check(pad.down(bindings: bindings).swallow, "a second click soon after")
    _ = pad.up()
    check(pad.engine.tick(now: pad.now + 0.31).contains(.tap(.playPause, zone: .topLeft, clicks: 2)), "makes two")

    pad = Pad()
    _ = pad.finger(5, 74)
    for _ in 0..<3 {
        _ = pad.down(bindings: bindings)
        _ = pad.up()
    }
    let three = pad.engine.tick(now: pad.now + 0.31)
    check(!three.contains { if case .tap = $0 { true } else { false } }, "three, with nothing on three, does nothing")

    pad = Pad()
    _ = pad.finger(5, 74)
    for _ in 0..<3 {
        _ = pad.down(bindings: bindings)
        _ = pad.up()
    }
    _ = pad.down(bindings: bindings)
    check(pad.up().effects.contains(.tap(.nextTrack, zone: .topLeft, clicks: 4)), "the highest count fires at once")

    // Moving on before it's settled.
    pad = Pad()
    _ = pad.finger(5, 74)
    _ = pad.down(bindings: bindings)
    _ = pad.up()
    _ = pad.lift()
    _ = pad.finger(middleX, middleY)
    let other = pad.down(bindings: bindings)
    check(!other.swallow, "a click elsewhere goes through")
    check(other.effects.contains(.tap(.mute, zone: .topLeft, clicks: 1)), "and the corner's click still counts")

    // A corner wins over the edge beneath it, unless it has no job.
    let surface = Surface.builtIn, feel = FeelSettings()
    check(Geometry.zone(x: 0.02, y: 0.98, surface: surface, feel: feel, bindings: plain) == .topLeft, "a corner with a job wins")
    check(Geometry.zone(x: 0.98, y: 0.98, surface: surface, feel: feel, bindings: plain) == .right, "without one, that spot belongs to the edge")
    check(Geometry.zone(x: 0.03, y: 0.02, surface: surface, feel: feel, bindings: plain) == .bottom || Geometry.zone(x: 0.03, y: 0.02, surface: surface, feel: feel, bindings: plain) == .left, "where two edges meet, one of them answers")
    check(Geometry.zone(x: 0.5, y: 0.02, surface: surface, feel: feel, bindings: plain) == .bottom, "the bottom middle is the bottom")
    check(Geometry.zone(x: 0.02, y: 0.5, surface: surface, feel: feel, bindings: plain) == .left, "the left middle is the left")
    check(Geometry.zone(x: 0.5, y: 0.5, surface: surface, feel: feel, bindings: plain) == nil, "the middle is nobody's")
    check(Geometry.zone(x: 0.2, y: 0.5, surface: surface, feel: feel, bindings: plain) == nil, "and neither is just past the strip")
}

func testFeel() {
    var feel = FeelSettings()
    let small = Surface.builtIn, big = Surface(widthMM: 160, heightMM: 115)
    let onSmall = Geometry.rect(.left, surface: small, feel: feel), onBig = Geometry.rect(.left, surface: big, feel: feel)
    check(abs(onSmall.maxX * small.widthMM - onBig.maxX * big.widthMM) < 0.001, "an edge is the same width in millimetres on any trackpad")

    feel.sideSpan = 0.25
    check(Geometry.zone(x: 0.98, y: 0.5, surface: small, feel: feel, bindings: plain) == nil, "side edges can be limited to the lower part")
    check(Geometry.zone(x: 0.98, y: 0.2, surface: small, feel: feel, bindings: plain) != nil, "the lower part still answers")

    feel = FeelSettings()
    feel.edgeMM = 200
    let huge = Geometry.rect(.left, surface: small, feel: feel)
    check(huge.maxX <= 0.5, "an absurd width can't swallow the whole trackpad")

    var pad = Pad()
    pad.engine.feel.requiredModifier = .option
    _ = pad.finger(right, middleY)
    check(!pad.down().swallow, "with a modifier required, a plain click is ordinary")
    pad = Pad()
    pad.engine.feel.requiredModifier = .option
    _ = pad.finger(right, middleY)
    check(pad.down(flags: Flag.option).swallow, "and with it held, it's a gesture")
    pad = Pad()
    pad.engine.feel.requiredModifier = .command
    _ = pad.finger(right, middleY)
    check(pad.down(flags: Flag.command).swallow, "⌘ can be the required one, despite normally keeping a click ordinary")
}

func testFailsafes() {
    // The worst thing Tavra could do is keep the pointer or a click.
    var pad = Pad()
    _ = pad.finger(right, 20)
    _ = pad.down()
    check(pad.engine.tick(now: pad.now + 1).isEmpty, "a held gesture isn't cut short")
    let silent = pad.engine.tick(now: pad.now + GestureEngine.watchdogSeconds + 1)
    check(silent.contains(.freezePointer(false)), "a gesture gone silent lets go of the pointer")
    check(!pad.engine.isBusy, "and ends")
    check(!pad.engine.mouseDragged(flags: 0, now: pad.now + 7), "and clicks go through again")

    pad = Pad()
    _ = pad.finger(30, 5)
    _ = pad.down()
    let reset = pad.engine.reset()
    check(reset.first == .timelineCancelled && reset.contains(.freezePointer(false)), "a reset cancels a seek and frees the pointer")
    check(pad.engine.reset().isEmpty, "a second reset does nothing")

    pad = Pad()
    _ = pad.finger(right, 20)
    _ = pad.down()
    // The up never came, and now there's a new click.
    _ = pad.lift()
    _ = pad.finger(middleX, middleY, id: 2)
    let next = pad.down()
    check(!next.swallow, "a lost release can't take the next click")
    check(next.effects.contains(.freezePointer(false)), "and the pointer is freed")

    pad = Pad()
    _ = pad.finger(right, 20)
    _ = pad.down()
    _ = pad.lift()
    check(pad.up().effects.contains(.freezePointer(false)), "lifting before the click finishes is fine")

    pad = Pad()
    check(!pad.up().swallow, "a release Tavra never saw the start of goes through")
    check(!pad.engine.mouseDragged(flags: 0, now: 1), "and so does a drag")
    check(pad.engine.tick(now: 1000).isEmpty, "and idle stays idle")
}

func testBindings() throws {
    var config = Config()
    check(config.bindings(forApp: nil) != nil, "on by default")
    check(config.bindings.slide(.right) == .volume && config.bindings.slide(.left) == .brightness && config.bindings.slide(.bottom) == .timeline, "starts with volume, brightness and the timeline")
    check(config.bindings.tap(.topRight, clicks: 1) == .playPause, "play or pause in a corner")
    check(config.bindings.tap(.topRight, clicks: 2) == .nextTrack, "and the next track on a second click")
    check(!config.bindings.has(.topLeft), "the other corners stay free")
    check(config.bindings.slide(.top) == .none, "the top edge stays free until asked")

    config.paused = true
    check(config.bindings(forApp: nil) == nil, "paused means nothing's in force")
    config.paused = false

    var figma = AppRule(bundleID: "com.figma.Desktop", name: "Figma", path: "/Applications/Figma.app")
    figma.bindings.slides[Zone.right.rawValue] = SlideAction.presets[1]
    config.apps = [figma, AppRule(bundleID: "com.game", name: "Game", path: "", off: true)]
    check(config.bindings(forApp: "com.figma.Desktop")?.slide(.right) == SlideAction.presets[1], "an app can change an edge")
    check(config.bindings(forApp: "com.figma.Desktop")?.slide(.left) == .brightness, "and keeps the rest")
    check(config.bindings(forApp: "com.other")?.slide(.right) == .volume, "other apps are untouched")
    check(config.bindings(forApp: "com.game") == nil, "an app can turn Tavra off")

    var cleared = Bindings()
    cleared.slides[Zone.right.rawValue] = SlideAction.none
    check(!config.bindings.merged(with: cleared).has(.right), "an app can switch one zone off")

    var corner = Bindings()
    corner.setTap(.playPause, zone: .topLeft, clicks: 2)
    corner.setTap(.mute, zone: .topRight, clicks: 3)
    let merged = config.bindings.merged(with: corner)
    check(merged.clickCounts(.topRight) == [3], "an app that changes a corner takes over all of it")
    check(merged.clickCounts(.topLeft) == [2], "and leaves the others")

    var mine = Bindings()
    mine.setTap(.mute, zone: .topRight, clicks: 1)
    mine.setTap(TapAction.none, zone: .topRight, clicks: 2)
    check(mine.clickCounts(.topRight) == [1], "a click count set to nothing doesn't count")
    mine.setTap(nil, zone: .topRight, clicks: 1)
    mine.setTap(nil, zone: .topRight, clicks: 2)
    check(!mine.has(.topRight), "clearing them all frees the corner")

    // Every kind of action survives the file.
    var all = Config()
    all.bindings.slides[Zone.top.rawValue] = SlideAction.presets[0]
    all.bindings.slides[Zone.bottom.rawValue] = .keyboardBrightness
    for (index, action) in [TapAction.playPause, .nextTrack, .previousTrack, TapAction.presets[0], .openApp(path: "/Applications/Notes.app", name: "Notes"),
                            .openURL("https://naqara.dev", browser: "/Applications/Safari.app"), .openPath("/tmp"), .shortcut("Focus")].enumerated() {
        all.bindings.setTap(action, zone: .bottomRight, clicks: index + 1)
    }
    all.apps = [figma]
    all.feel.edgeMM = 9
    all.feel.requiredModifier = .shift
    let again = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(all))
    check(again == all, "every setting and action survives saving")

    let empty = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
    check(empty == Config(), "an empty file gets the defaults")
    let old = try JSONDecoder().decode(Config.self, from: Data(#"{"feel":{"edgeMM":9},"onboarded":true}"#.utf8))
    check(old.feel.edgeMM == 9 && old.feel.stepMM == 4 && old.onboarded && old.bindings == .starter, "a file from an older version keeps what it has")

    check(TapAction.openURL("https://naqara.dev", browser: nil).title == "naqara.dev", "links read cleanly")
    check(TapAction.openApp(path: "/x", name: "Notes").title == "Open Notes", "apps too")
    check(SlideAction.presets.allSatisfy { if case .keys = $0 { true } else { false } }, "the slide presets are key pairs")
}

func testSeek() {
    check(Seek.route(front: Seek.music, running: [Seek.music]) == .script(player: Seek.music), "Music in front answers for itself")
    check(Seek.route(front: Seek.spotify, running: [Seek.spotify, Seek.music]) == .script(player: Seek.spotify), "and so does Spotify")
    check(Seek.route(front: "com.google.Chrome", running: [Seek.spotify]) == .arrows, "a browser in front means the video in it, not the music behind")
    check(Seek.route(front: "com.apple.dt.Xcode", running: [Seek.spotify]) == .script(player: Seek.spotify), "working elsewhere, an open music app is what's meant")
    check(Seek.route(front: "com.apple.dt.Xcode", running: [Seek.music]) == .script(player: Seek.music), "Music too")
    check(Seek.route(front: "com.apple.dt.Xcode", running: []) == .nothing, "no player, no arrows: they'd only move a text cursor")
    check(Seek.route(front: nil, running: []) == .nothing, "and nothing in front is nothing")

    let forward = Seek.arrowPresses(seconds: 62, arrowSeconds: 5)
    check(forward.count == 12 && forward.forward, "a jump becomes whole arrow presses")
    let back = Seek.arrowPresses(seconds: -10, arrowSeconds: 10)
    check(back.count == 1 && !back.forward, "backwards too")
    check(Seek.arrowPresses(seconds: 2, arrowSeconds: 5).count == 0, "under half a press is none")
    check(Seek.arrowPresses(seconds: 100_000, arrowSeconds: 1).count == 120, "and never a flood")

    check(Seek.target(position: 100, duration: 300, jump: 60) == 160, "a jump lands where it should")
    check(Seek.target(position: 10, duration: 300, jump: -60) == 0, "not before the start")
    check(Seek.target(position: 290, duration: 300, jump: 60) == 299, "and not past the end, which would skip the track")

    check(Seek.clock(65) == "1:05", "clock")
    check(Seek.clock(3729) == "1:02:09", "clock with hours")
    check(Seek.signedClock(-10) == "−0:10", "signed back")
    check(Seek.signedClock(65) == "+1:05", "signed forward")

    let parsed = Seek.parse("12,5|300|Song | with a bar")
    check(parsed?.position == 12.5 && parsed?.duration == 300 && parsed?.title == "Song | with a bar", "a reply in any region's numbers")
    check(Seek.parse("12.5|300.25|Song")?.duration == 300.25, "with a dot too")
    check(Seek.parse("") == nil, "stopped gives nothing")
    check(Seek.parse("a|b|c") == nil, "nonsense gives nothing")
    check(Seek.parse("0|0|Live") == nil, "something with no length can't be scrubbed")

    check(Seek.script(toJump: Seek.spotify, to: 12.34).contains("to 12.3"), "a jump always writes a dot, whatever the region")
    check(Seek.script(toRead: Seek.spotify).contains("/ 1000"), "Spotify counts in milliseconds")
    check(!Seek.script(toRead: Seek.music).contains("/ 1000"), "Music in seconds")
}

func testTrackpadCheck() {
    let surface = Surface.builtIn, feel = FeelSettings()
    func finger(_ x: Double, _ y: Double) -> [Finger] { [Finger(id: 1, x: x / surface.widthMM, y: y / surface.heightMM)] }
    var check = TrackpadCheck()
    check.current == .right ? check_(true, "it starts by asking for the right edge") : check_(false, "it starts by asking for the right edge")
    check_(!check.update(fingers: finger(120, 38), surface: surface, feel: feel, now: 1), "the first moment on an edge isn't enough")
    check_(!check.update(fingers: finger(120, 38), surface: surface, feel: feel, now: 1.05), "nor is brushing past it")
    check_(check.update(fingers: finger(120, 38), surface: surface, feel: feel, now: 1.2), "resting there is")
    check_(check.found == [.right] && check.current == .left, "then it asks for the left")
    check_(!check.update(fingers: finger(120, 38), surface: surface, feel: feel, now: 1.4), "the same edge doesn't count twice")
    check_(check.found == [.right], "still one")

    _ = check.update(fingers: finger(62, 38), surface: surface, feel: feel, now: 2)
    check_(check.found == [.right], "the middle isn't an edge")
    _ = check.update(fingers: finger(5, 38), surface: surface, feel: feel, now: 2.1)
    _ = check.update(fingers: [], surface: surface, feel: feel, now: 2.15)
    _ = check.update(fingers: finger(5, 38), surface: surface, feel: feel, now: 2.2)
    check_(check.found == [.right], "lifting restarts the wait")

    // Ahead of the instructions is fine.
    _ = check.update(fingers: finger(62, 72), surface: surface, feel: feel, now: 3)
    check_(check.update(fingers: finger(62, 72), surface: surface, feel: feel, now: 3.2), "any edge counts, in any order")
    check_(check.current == .left, "and it still wants the one that's left")

    // Two fingers tell us nothing about which edge is which.
    let two = finger(5, 38) + [Finger(id: 2, x: 0.5, y: 0.5)]
    _ = check.update(fingers: two, surface: surface, feel: feel, now: 4)
    check_(!check.update(fingers: two, surface: surface, feel: feel, now: 4.2), "two fingers don't count")

    _ = check.update(fingers: finger(5, 38), surface: surface, feel: feel, now: 5)
    check_(check.update(fingers: finger(5, 38), surface: surface, feel: feel, now: 5.2), "the left edge")
    _ = check.update(fingers: finger(62, 5), surface: surface, feel: feel, now: 6)
    check_(check.update(fingers: finger(62, 5), surface: surface, feel: feel, now: 6.2), "and the bottom")
    check_(check.isDone && check.current == nil, "that's all four")
    check_(!check.needsHint(now: 1000), "and nothing more to suggest")

    var stuck = TrackpadCheck()
    _ = stuck.update(fingers: [], surface: surface, feel: feel, now: 1)
    check_(!stuck.needsHint(now: 5), "no hint straight away")
    check_(stuck.needsHint(now: 12), "after a while, a hint")
    _ = stuck.update(fingers: finger(120, 38), surface: surface, feel: feel, now: 12)
    _ = stuck.update(fingers: finger(120, 38), surface: surface, feel: feel, now: 12.2)
    check_(!stuck.needsHint(now: 13), "finding one starts the wait over")

    check_(TrackpadCheck.edge(x: 0.99, y: 0.99, surface: surface, feel: feel) != nil, "a corner counts as whichever edge is nearer")
    check_(TrackpadCheck.edge(x: 0.5, y: 0.5, surface: surface, feel: feel) == nil, "the middle as none")
    // The check doesn't depend on what the edges are set to do.
    var wide = FeelSettings(); wide.edgeMM = 25
    check_(TrackpadCheck.edge(x: 0.82, y: 0.5, surface: surface, feel: wide) == .right, "it follows the width set")
}

func check_(_ condition: Bool, _ what: String) { check(condition, what) }

@main enum Run {
    static func main() throws {
        testOrdinaryClicks(); testSliding(); testTimeline(); testCorners(); testFeel(); testFailsafes(); try testBindings(); testSeek(); testTrackpadCheck()
        if failures.isEmpty {
            print("✓ \(passed) checks passed")
        } else {
            print("✗ \(failures.count) failed, \(passed) passed")
            failures.forEach { print("  \($0)") }
            exit(1)
        }
    }
}
