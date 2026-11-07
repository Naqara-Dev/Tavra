import AppKit
import SwiftUI

/// A short welcome: what Tavra does, the one permission it needs, and trying it on your own trackpad.
struct OnboardingView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            Theme.window
            Group {
                switch model.onboardingStep {
                case .welcome: welcome
                case .check: trackpadCheck
                case .permission: permission
                case .tryIt: tryIt
                case .done: done
                }
            }
            .frame(width: model.onboardingStep == .tryIt || model.onboardingStep == .check ? 760 : 500, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(model.onboardingStep)
            .transition(.blurReplace.combined(with: .offset(y: 10)))
            WindowDragArea().frame(height: 28)
        }
        .animation(Motion.settle, value: model.onboardingStep)
    }

    private func heading(_ title: String, _ detail: String, size: CGFloat = 32) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: size, weight: .light)).tracking(-0.8).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var icon: some View {
        if let image = NSImage(named: "AppIcon") {
            Image(nsImage: image).resizable().frame(width: 52, height: 52)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 26) {
            IntroMark()
            VStack(alignment: .leading, spacing: 9) {
                WordReveal(text: "Make every touch do more", size: 36)
                Text("The edges and corners of your trackpad become controls you can feel. The center stays yours.")
                    .font(.system(size: 14, weight: .light)).foregroundStyle(Theme.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    .arrive(after: 0.75)
            }
            VStack(alignment: .leading, spacing: 0) {
                line("speaker.wave.2", "Sound", "On the right edge").arrive(after: 0.9)
                line("sun.max", "Light", "On the left edge").arrive(after: 0.97)
                line("play.square", "What's playing", "On the bottom edge").arrive(after: 1.04)
                line("square.grid.2x2", "Anything else", "Corners, and a set for each app").arrive(after: 1.11)
                Hairline().arrive(after: 1.18)
            }
            Button("Check My Trackpad") { model.onboardingStep = .check }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .arrive(after: 1.25)
        }
    }

    private func line(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.accent).frame(width: 28, alignment: .leading)
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.ink).frame(width: 130, alignment: .leading)
                Text(detail).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary)
            }
            .padding(.vertical, 11)
        }
    }

    // MARK: The trackpad check

    private var nextAfterCheck: OnboardingStep { model.isTrusted ? .tryIt : .permission }

    private var checkTitle: String {
        if model.devices.isEmpty { return "No trackpad found" }
        guard let current = model.check.current else { return "Every edge reads" }
        return "Touch the \(current.title.lowercased())"
    }

    private var checkDetail: String {
        if model.devices.isEmpty { return "Tavra needs a Force Touch trackpad: the one in a MacBook, or a Magic Trackpad. It'll notice as soon as one connects." }
        if model.check.isDone { return "Your trackpad reports all four edges. Nothing was clicked, and no permission was needed for this." }
        if model.checkNeedsHint { return "Nothing yet from this edge. Rest one finger right against it, with no other fingers down." }
        return "One finger, right against the edge. Just rest it there: no need to click."
    }

    private var trackpadCheck: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading(checkTitle, checkDetail)
                .id(checkTitle)
                .transition(.blurReplace)
            HStack(alignment: .top, spacing: 32) {
                CheckMap(model: model).frame(width: 440, height: 271)
                VStack(alignment: .leading, spacing: 0) {
                    deviceLine
                    ForEach(TrackpadCheck.order) { zone in edgeLine(zone) }
                    Hairline()
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 16) {
                Button(model.check.isDone ? "Continue" : model.devices.isEmpty ? "Continue Anyway" : "Skip") { model.onboardingStep = nextAfterCheck }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                if !model.check.isDone, !model.devices.isEmpty, !model.check.found.isEmpty {
                    Button("Start Again") { model.onboardingStep = .check }
                        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .animation(Motion.settle, value: model.check)
    }

    private var deviceLine: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                Image(systemName: model.devices.isEmpty ? "magnifyingglass" : "rectangle.dashed").font(.system(size: 12, weight: .light))
                    .foregroundStyle(model.devices.isEmpty ? Theme.warm : Theme.secondary).frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    if let device = model.devices.first {
                        Text(device.isBuiltIn ? "Built-in trackpad" : "Magic Trackpad").font(.system(size: 13)).foregroundStyle(Theme.ink)
                        Text("\(Int(device.surface.widthMM.rounded())) × \(Int(device.surface.heightMM.rounded())) mm\(model.devices.count > 1 ? ", and \(model.devices.count - 1) more" : "")")
                            .font(.system(size: 11.5, weight: .light)).foregroundStyle(Theme.tertiary)
                    } else {
                        Text("Looking for a trackpad…").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }

    /// Points at the edge it means.
    private func edgeIcon(_ zone: Zone) -> String {
        switch zone {
        case .left: "arrow.left.to.line"
        case .right: "arrow.right.to.line"
        case .top: "arrow.up.to.line"
        default: "arrow.down.to.line"
        }
    }

    private func edgeLine(_ zone: Zone) -> some View {
        let found = model.check.found.contains(zone)
        let isNow = model.check.current == zone && !model.devices.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(spacing: 10) {
                Image(systemName: found ? "checkmark" : edgeIcon(zone)).font(.system(size: 11.5, weight: found ? .medium : .light))
                    .foregroundStyle(found ? Theme.accent : isNow ? Theme.ink : Theme.tertiary).frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: found)
                Text(zone.title).font(.system(size: 13, weight: isNow ? .regular : .light)).foregroundStyle(found ? Theme.secondary : isNow ? Theme.ink : Theme.tertiary)
                Spacer()
                if found {
                    Text("Reads").font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                        .transition(.blurReplace.combined(with: .offset(x: 6)))
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 26) {
            icon
            heading("One permission", "Tavra needs Accessibility access to press the volume and brightness keys for you, and to keep edge clicks out of your apps.")
            VStack(alignment: .leading, spacing: 0) {
                promise("Never what you type", "It only listens for clicks, and never for keys.")
                promise("Nothing leaves your Mac", "Tavra doesn't use the network at all.")
                promise("Always ordinary if unsure", "Only a click that starts on an edge or corner is held back.")
                Hairline()
            }
            HStack(spacing: 16) {
                Button("Open Accessibility Settings") {
                    model.askForAccessibility()
                    model.openAccessibilitySettings()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                Button("Not Now") { model.finishOnboarding() }
                    .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Text("Turn on Tavra in the list. This screen moves on by itself.")
                .font(.system(size: 12, weight: .light)).foregroundStyle(Theme.tertiary)
        }
    }

    private func promise(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.ink).frame(width: 190, alignment: .leading)
                Text(detail).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary)
            }
            .padding(.vertical, 11)
        }
    }

    private struct Goal: Identifiable {
        var id: Zone { zone }
        var zone: Zone
        var text: String
        var icon: String
    }

    private var goals: [Goal] {
        let b = model.config.bindings
        let corner = Zone.corners.first { b.has($0) }
        return ([Zone.right, .left, .bottom] + [corner].compactMap { $0 }).filter { b.has($0) }.map { zone in
            let name = zone.isCorner ? b.tap(zone, clicks: b.clickCounts(zone).first ?? 1).title : b.slide(zone).title
            let icon = zone.isCorner ? b.tap(zone, clicks: b.clickCounts(zone).first ?? 1).icon : b.slide(zone).icon
            return Goal(zone: zone, text: zone.isCorner ? "Click the \(zone.title.lowercased()): \(name.lowercased())" : "Press the \(zone.title.lowercased()) and slide: \(name.lowercased())", icon: icon)
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("Now for real", "Press until the trackpad clicks, then slide. Light follows your finger.")
            HStack(alignment: .top, spacing: 30) {
                PadMap(model: model, bindings: model.config.bindings, showsCaption: false).frame(width: 380, height: 234)
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(goals) { goal in
                        let done = model.tried.contains(goal.zone)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: done ? "checkmark" : goal.icon).font(.system(size: 11.5, weight: done ? .medium : .light))
                                .foregroundStyle(done ? Theme.accent : Theme.secondary).frame(width: 16)
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: done)
                            Text(goal.text).font(.system(size: 13, weight: .light)).foregroundStyle(done ? Theme.secondary : Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 6)
            }
            HStack(spacing: 16) {
                Button(goals.allSatisfy { model.tried.contains($0.zone) } ? "Continue" : "Skip") { model.onboardingStep = .done }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                if !model.isTrusted {
                    Text("Gestures start once Accessibility is on.").font(.system(size: 12, weight: .light)).foregroundStyle(Theme.warm)
                }
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 26) {
            icon
            heading("That's all", "Tavra lives in the menu bar and stays out of your way. Change any edge or corner, or give an app its own, whenever you like.")
            HStack(spacing: 16) {
                Button("Choose What Each Part Does") { model.finishOnboarding() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Toggle("Open at login", isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }
}

/// The trackpad to scale. Asked-for edges carry a current, found ones charge up, and the last one sets
/// light running round the whole thing.
private struct CheckMap: View {
    var model: AppModel

    private var surface: Surface { model.devices.first?.surface ?? .builtIn }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let rects = TrackpadCheck.order.map { zone -> (zone: Zone, rect: CGRect) in
                let r = Geometry.rect(zone, surface: surface, feel: model.config.feel)
                return (zone, CGRect(x: r.minX * size.width, y: (1 - r.maxY) * size.height, width: (r.maxX - r.minX) * size.width, height: (r.maxY - r.minY) * size.height))
            }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card.opacity(0.55))
                ForEach(rects, id: \.zone) { item in
                    ChargingStrip(isFound: model.check.found.contains(item.zone),
                                  isAsked: model.check.current == item.zone && !model.devices.isEmpty,
                                  isVertical: item.zone == .left || item.zone == .right)
                        .frame(width: item.rect.width, height: item.rect.height)
                        .position(x: item.rect.midX, y: item.rect.midY)
                }
                TouchField(router: model.router, size: size, zones: rects.map(\.rect))
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.line)
                if model.check.isDone { CompletionLight().frame(width: size.width, height: size.height) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
