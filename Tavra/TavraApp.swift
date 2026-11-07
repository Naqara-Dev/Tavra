import AppKit
import SwiftUI

@main
struct TavraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window("Tavra", id: "main") {
            RootView(model: model)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(scheme)
                .background(WindowOpener(model: model))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                ForEach(Array(Page.allCases.enumerated()), id: \.element) { index, page in
                    Button(page.title) { model.page = page }.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
        }

        // The status item reports its visibility back through this binding every time it's updated, and
        // an @Observable write redraws even when the value is the same: only a real change may write.
        MenuBarExtra(isInserted: Binding(get: { model.config.showInMenuBar }, set: { shown in
            if model.config.showInMenuBar != shown { model.config.showInMenuBar = shown }
        })) {
            MenuPanel(model: model).preferredColorScheme(scheme)
        } label: {
            Image(systemName: model.config.paused ? "hand.raised.slash" : "hand.tap")
                .background(WindowOpener(model: model))
        }
        .menuBarExtraStyle(.window)
    }

    private var scheme: ColorScheme? {
        switch model.config.appearance {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        // A menu bar app doesn't open a window on every login, once it's set up and has somewhere to live.
        #if DEBUG
        if UserDefaults.standard.string(forKey: "TavraPage") != nil || UserDefaults.standard.string(forKey: "TavraStep") != nil { return }
        #endif
        if model.config.onboarded, model.config.showInMenuBar {
            DispatchQueue.main.async {
                for window in NSApp.windows where window.canBecomeMain { window.close() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.quitting()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !model.config.showInMenuBar
    }

    /// Opening Tavra again while it runs shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model.openMainWindow?() }
        return true
    }
}

/// Hands the model a way to open the window, which only views get.
private struct WindowOpener: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            model.openMainWindow = {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.onboardingOpen {
                OnboardingView(model: model)
            } else {
                HStack(spacing: 0) {
                    Sidebar(model: model)
                    Rectangle().fill(Theme.line).frame(width: 1)
                    ZStack(alignment: .top) {
                        Group {
                            switch model.page {
                            case .trackpad: TrackpadPage(model: model)
                            case .apps: AppsPage(model: model)
                            case .feel: FeelPage(model: model)
                            case .settings: SettingsPage(model: model)
                            }
                        }
                        .id(model.page)
                        .transition(.opacity.combined(with: .offset(y: 7)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        WindowDragArea().frame(height: 28)
                    }
                    .background(Theme.window)
                }
                .animation(.easeOut(duration: 0.22), value: model.page)
                .transition(.opacity)
            }
        }
        .animation(Motion.settle, value: model.onboardingOpen)
        .background(FocusReset(page: model.page))
        .background(Theme.window)
        .ignoresSafeArea()
        .id(Theme.accentChoice)
        .tint(Theme.accent)
    }
}

private struct Sidebar: View {
    @Bindable var model: AppModel
    @Namespace private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack { WindowDragArea() }.frame(height: 44)
            HStack(spacing: 9) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                }
                Text("Tavra").font(.system(size: 15)).tracking(-0.2).foregroundStyle(Theme.ink)
            }
            .padding(.horizontal, 12).padding(.bottom, 16)
            ForEach(Page.allCases) { page in
                SidebarRow(page: page, isOn: model.page == page, highlight: highlight) { model.page = page }
            }
            Spacer()
            footer
        }
        .padding(.horizontal, 10).padding(.bottom, 14)
        .frame(width: 190)
        .background(Theme.sidebar)
        .animation(Motion.glide, value: model.page)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: statusIcon).font(.system(size: 10.5, weight: .light)).foregroundStyle(statusColor).frame(width: 14)
            Text(statusText).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 12)
    }

    private var statusIcon: String {
        if model.config.paused { return "pause" }
        return model.tapRunning ? "checkmark" : "lock"
    }

    private var statusColor: Color {
        !model.config.paused && !model.tapRunning ? Theme.warm : Theme.tertiary
    }

    private var statusText: String {
        if model.config.paused { return "Paused" }
        return model.tapRunning ? "Ready" : "Needs permission"
    }
}

private struct SidebarRow: View {
    var page: Page
    var isOn: Bool
    var highlight: Namespace.ID
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.icon).font(.system(size: 13, weight: .light)).frame(width: 18)
                    .foregroundStyle(isOn ? Theme.accent : Theme.secondary)
                Text(page.title).font(.system(size: 13)).foregroundStyle(isOn ? Theme.ink : Theme.secondary)
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.card).matchedGeometryEffect(id: "page", in: highlight)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.card.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The panel under the menu bar item: is it on, and a way out of the way, right now.
struct MenuPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Tavra").font(.system(size: 14)).foregroundStyle(Theme.ink)
                Spacer()
                Toggle("", isOn: Binding(get: { !model.config.paused }, set: { model.config.paused = !$0 }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            if !model.isTrusted {
                Text("Waiting for Accessibility permission.").font(.system(size: 12, weight: .light)).foregroundStyle(Theme.warm)
            }
            PadMap(model: model, bindings: model.effectiveBindings, showsCaption: false).frame(height: 150)
            if let gesture = model.lastGesture {
                Text(gesture).font(.system(size: 12, weight: .light)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            if let app = model.frontApp, app.bundleIdentifier != Bundle.main.bundleIdentifier, let id = app.bundleIdentifier {
                Hairline()
                HStack {
                    Text("Leave \(app.localizedName ?? "this app") alone").font(.system(size: 12.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.rule(for: id)?.off ?? false }, set: { model.setOff($0, forFrontApp: app) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
            }
            Hairline()
            HStack {
                Button("Open Tavra") { model.openMainWindow?() }
                    .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.ink)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(Theme.window)
    }
}

extension AppModel {
    /// What's in force for whichever app is in front, for showing.
    var effectiveBindings: Bindings {
        config.bindings(forApp: frontApp?.bundleIdentifier) ?? Bindings()
    }
}
