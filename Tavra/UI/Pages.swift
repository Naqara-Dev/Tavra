import AppKit
import SwiftUI

/// The trackpad, and what each part of it does.
struct TrackpadPage: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader("Trackpad", subtitle: "Touch a zone to change what it does.") {
                    Button("Swap Left and Right") {
                        let left = model.config.bindings.slides[Zone.left.rawValue]
                        model.config.bindings.slides[Zone.left.rawValue] = model.config.bindings.slides[Zone.right.rawValue]
                        model.config.bindings.slides[Zone.right.rawValue] = left
                    }
                    .buttonStyle(QuietButtonStyle(tint: Theme.secondary))
                }
                StatusNotice(model: model)
            }
            .padding(.horizontal, 36).padding(.top, 44).padding(.bottom, 24)
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 14) {
                    PadMap(model: model, bindings: model.config.bindings, selected: model.selectedZone) { model.selectedZone = $0 }
                    Text(model.lastGesture ?? "Try it: your fingers show up here as you touch the trackpad.")
                        .font(.system(size: 12.5, weight: .light)).foregroundStyle(model.lastGesture == nil ? Theme.tertiary : Theme.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                ScrollView {
                    ZoneEditor(model: model, zone: model.selectedZone, bindings: $model.config.bindings, base: nil)
                        .id(model.selectedZone)
                        .transition(.blurReplace)
                }
                .scrollIndicators(.never)
                .frame(width: 290)
                .animation(.easeOut(duration: 0.2), value: model.selectedZone)
            }
            .padding(.horizontal, 36).padding(.bottom, 32)
        }
    }
}

/// Only here when something's in the way.
struct StatusNotice: View {
    var model: AppModel

    var body: some View {
        if !model.isTrusted {
            notice("Gestures are waiting for permission", "Tavra needs Accessibility access to press the volume keys for you and keep edge clicks out of your apps. It never records what you type.") {
                Button("Grant Access") {
                    model.askForAccessibility()
                    model.openAccessibilitySettings()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        } else if model.config.paused {
            notice("Tavra is paused", "Every click on the trackpad is an ordinary click until you resume.") {
                Button("Resume") { model.config.paused = false }.buttonStyle(PrimaryButtonStyle())
            }
        } else if model.devices.isEmpty {
            notice("No trackpad found", "Tavra needs a Force Touch trackpad, built in or a Magic Trackpad. It'll notice when one connects.") { EmptyView() }
        }
    }

    private func notice<Trailing: View>(_ title: String, _ detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5)).foregroundStyle(Theme.ink)
                Text(detail).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Things an app does differently.
struct AppsPage: View {
    @Bindable var model: AppModel
    @State private var chosen: String?
    @State private var zone = Zone.right

    private var index: Int? { model.config.apps.firstIndex { $0.bundleID == chosen } }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader("Apps", subtitle: "Give an app its own gestures, or have Tavra leave it alone.") {
                MenuButton(minWidth: 240, alignRight: true) { additions } label: {
                    Text("Add App").lineLimit(1).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.window)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink))
                }
                .fixedSize()
            }
            if model.config.apps.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text("Every app uses the same gestures").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.secondary)
                    Text("Tabs on the top edge in your browser, zoom on the right edge in Figma, nothing at all in a game.")
                        .font(.system(size: 12.5, weight: .light)).foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 28) {
                    list.frame(width: 210)
                    if let index { detail(index) } else {
                        Text("Choose an app.").font(.system(size: 13, weight: .light)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 36).padding(.top, 44).padding(.bottom, 32)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { chosen = chosen ?? model.config.apps.first?.bundleID }
    }

    private var additions: [DropdownEntry] {
        var entries: [DropdownEntry] = [.item("Choose from Applications…", icon: "folder", id: "choose") { choose() }]
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && model.rule(for: $0.bundleIdentifier ?? "") == nil }
        if !running.isEmpty {
            entries.append(.divider("running"))
            entries.append(.heading("Open now"))
            for app in running.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
                entries.append(.item(app.localizedName ?? "App", id: app.bundleIdentifier ?? UUID().uuidString) {
                    model.addRunning(app)
                    chosen = app.bundleIdentifier
                })
            }
        }
        return entries
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addApp(url: url)
        chosen = Bundle(url: url)?.bundleIdentifier
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.config.apps) { rule in
                Button { chosen = rule.bundleID } label: {
                    HStack(spacing: 9) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: rule.path)).resizable().frame(width: 20, height: 20).opacity(rule.off ? 0.45 : 1)
                        Text(rule.name).font(.system(size: 13)).foregroundStyle(chosen == rule.bundleID ? Theme.ink : Theme.secondary).lineLimit(1)
                        Spacer()
                        if rule.off { Text("Off").font(.system(size: 11)).foregroundStyle(Theme.tertiary) }
                    }
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(chosen == rule.bundleID ? Theme.card : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tavraContextMenu {
                    [.item("Remove", icon: "trash", tint: Theme.danger) { remove(rule) }]
                }
            }
        }
    }

    private func remove(_ rule: AppRule) {
        model.config.apps.removeAll { $0.bundleID == rule.bundleID }
        if chosen == rule.bundleID { chosen = model.config.apps.first?.bundleID }
    }

    @ViewBuilder private func detail(_ index: Int) -> some View {
        let rule = model.config.apps[index]
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text(rule.name).font(.system(size: 19, weight: .light)).tracking(-0.3).foregroundStyle(Theme.ink)
                Spacer()
                Toggle("Leave this app alone", isOn: $model.config.apps[index].off)
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Button("Remove") { remove(rule) }.buttonStyle(QuietButtonStyle(tint: Theme.danger))
            }
            if rule.off {
                Text("With \(rule.name) in front, every click on the trackpad is an ordinary click.")
                    .font(.system(size: 13, weight: .light)).foregroundStyle(Theme.tertiary)
            } else {
                HStack(alignment: .top, spacing: 28) {
                    PadMap(model: model, bindings: model.config.bindings.merged(with: rule.bindings), selected: zone, onSelect: { zone = $0 }, showsCaption: false)
                        .frame(maxWidth: .infinity)
                    ScrollView {
                        ZoneEditor(model: model, zone: zone, bindings: $model.config.apps[index].bindings, base: model.config.bindings)
                    }
                    .scrollIndicators(.never)
                    .frame(width: 260)
                }
            }
        }
    }
}

/// How gestures feel under the finger.
struct FeelPage: View {
    @Bindable var model: AppModel
    private var feel: Binding<FeelSettings> { $model.config.feel }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                PageHeader("Feel", subtitle: "All in millimetres, so a slide feels the same on any trackpad.")
                HStack(alignment: .top, spacing: 36) {
                    VStack(alignment: .leading, spacing: 32) {
                        Section2("The zones") {
                            sliderRow("Edge width", note: "Thinner stays further out of the way.", value: feel.edgeMM, range: 6...30, unit: "mm", step: 1)
                            sliderRow("Corner size", value: feel.cornerMM, range: 10...40, unit: "mm", step: 1)
                            sliderRow("Side edges reach up", note: "From the bottom. Limit them if your palms rest high.", value: Binding(get: { model.config.feel.sideSpan * 100 }, set: { model.config.feel.sideSpan = $0 / 100 }), range: 25...100, unit: "%", step: 5)
                        }
                        Section2("Sliding") {
                            sliderRow("Distance per step", note: "Shorter is faster. Hold ⇧⌥ for quarter steps on volume and brightness.", value: feel.stepMM, range: 2...10, unit: "mm", step: 0.5, decimals: 1)
                            row("Flip direction") { switchFor(feel.invert) }
                            row("Keep the pointer still while sliding") { switchFor(feel.freezePointer) }
                            row("A tick under your finger", note: "On a Force Touch trackpad.") {
                                Segments(options: HapticChoice.allCases, selection: feel.haptics) { $0.title }
                            }
                        }
                        Section2("Media timeline") {
                            row("A slide across the whole trackpad covers") {
                                Segments(options: [60.0, 300.0, 600.0, 1800.0], selection: feel.timelineSeconds) { "\(Int($0 / 60)) min" }
                            }
                            sliderRow("One arrow key jumps", note: "In browsers and video players. YouTube is 5, Netflix is 10.", value: feel.arrowSeconds, range: 1...30, unit: "s", step: 1)
                            row("Show the seek bar") { switchFor($model.config.seekHUD) }
                        }
                        Section2("Clicks") {
                            row("Only with this key held", note: "⌘ and ⌃ always keep a click ordinary, unless you pick one of them here.") {
                                Segments(options: ModifierChoice.allCases, selection: feel.requiredModifier) { $0.title }
                            }
                            sliderRow("Time between corner clicks", value: Binding(get: { model.config.feel.multiClickSeconds * 1000 }, set: { model.config.feel.multiClickSeconds = $0 / 1000 }), range: 150...600, unit: "ms", step: 25)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        PadMap(model: model, bindings: model.config.bindings, showsCaption: false).frame(height: 190)
                        Text("Changes apply as you make them.").font(.system(size: 12, weight: .light)).foregroundStyle(Theme.tertiary)
                    }
                    .frame(width: 300)
                }
            }
            .padding(.horizontal, 36).padding(.top, 44).padding(.bottom, 32)
        }
        .scrollIndicators(.never)
    }

    private func switchFor(_ value: Binding<Bool>) -> some View {
        Toggle("", isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }

    private func sliderRow(_ title: String, note: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double, decimals: Int = 0) -> some View {
        row(title, note: note) {
            HStack(spacing: 12) {
                ThinSlider(value: value, range: range, step: step).frame(width: 130)
                NumberBox(value: value, unit: unit, range: range, width: 32, decimals: decimals)
            }
        }
    }
}

struct Section2<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title)
            VStack(alignment: .leading, spacing: 14) { content }
        }
    }
}

func row<Content: View>(_ title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .center, spacing: 20) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.ink)
            if let note {
                Text(note).font(.system(size: 11.5, weight: .light)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        Spacer(minLength: 20)
        content()
    }
}

/// A state, in words with an icon. Colour is saved for what needs attention.
private struct StatusText: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .light))
            Text(text).font(.system(size: 12.5))
        }
        .foregroundStyle(Theme.secondary)
    }
}

struct SettingsPage: View {
    @Bindable var model: AppModel
    @State private var accent = Theme.accentChoice

    private func switchFor(_ value: Binding<Bool>) -> some View {
        Toggle("", isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                PageHeader("Settings")
                Section2("Status") {
                    row("Accessibility", note: "To press volume and brightness keys for you, and keep edge clicks out of your apps. Tavra never records what you type.") {
                        if model.isTrusted {
                            StatusText(icon: "checkmark", text: "Allowed")
                        } else {
                            Button("Grant Access") {
                                model.askForAccessibility()
                                model.openAccessibilitySettings()
                            }
                            .buttonStyle(QuietButtonStyle())
                        }
                    }
                    row("Clicks", note: "Tavra sees a click before apps do, and keeps only the ones that start a gesture.") {
                        StatusText(icon: model.tapRunning ? "cursorarrow.click" : "minus", text: model.tapRunning ? "Listening" : "Off")
                    }
                    row("Trackpads") {
                        if model.devices.isEmpty {
                            Text("None found").font(.system(size: 12.5)).foregroundStyle(Theme.warm)
                        } else {
                            VStack(alignment: .trailing, spacing: 3) {
                                ForEach(Array(model.devices.enumerated()), id: \.offset) { _, device in
                                    Text("\(device.isBuiltIn ? "Built in" : "External"), \(Int(device.surface.widthMM.rounded())) × \(Int(device.surface.heightMM.rounded())) mm")
                                        .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    }
                    row("Pause Tavra", note: "Every click becomes an ordinary click.") { switchFor($model.config.paused) }
                }
                Section2("Look") {
                    row("Appearance") { Segments(options: AppearanceChoice.allCases, selection: $model.config.appearance) { $0.title } }
                    row("Accent") {
                        HStack(spacing: 8) {
                            ForEach(Theme.Accent.allCases) { option in
                                Button {
                                    Theme.accentChoice = option
                                    accent = option
                                    model.page = .settings
                                } label: {
                                    Circle().fill(option.color).frame(width: 16, height: 16)
                                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: accent == option ? 1.5 : 0).padding(-3))
                                        .frame(width: 24, height: 24).contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help(option.title)
                            }
                        }
                    }
                }
                Section2("In the system") {
                    row("Open at login") {
                        Toggle("", isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                    row("Show in the menu bar", note: "Without it, open Tavra again to see this window.") { switchFor($model.config.showInMenuBar) }
                    row("Show in the Dock") {
                        Toggle("", isOn: Binding(get: { model.config.showInDock }, set: {
                            model.config.showInDock = $0
                            model.applyDockPolicy()
                        })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    }
                }
                Section2("Start over") {
                    row("Show the welcome guide again") {
                        Button("Show") {
                            model.onboardingStep = .welcome
                            model.resetTried()
                            model.onboardingOpen = true
                        }
                        .buttonStyle(QuietButtonStyle())
                    }
                    row("Put every gesture back as it was") {
                        Button("Reset") {
                            model.config.bindings = .starter
                            model.config.feel = FeelSettings()
                        }
                        .buttonStyle(QuietButtonStyle(tint: Theme.danger))
                    }
                }
                Text("Tavra \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""). Touches never leave your Mac.")
                    .font(.system(size: 12, weight: .light)).foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 36).padding(.top, 44).padding(.bottom, 32)
        }
        .scrollIndicators(.never)
    }
}
