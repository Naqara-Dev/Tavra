import AppKit
import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1).fixedSize()
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.window)
            .padding(.horizontal, 14).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .lineLimit(1).fixedSize()
            .font(.system(size: 13))
            .foregroundStyle(tint)
            .padding(.horizontal, 14).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Motion.snap, value: configuration.isPressed)
    }
}

/// A page's title, with room for what belongs beside it.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 28, weight: .regular)).tracking(-0.7).foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 13, weight: .light)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

/// A quiet section name above a hairline.
struct SectionTitle: View {
    var title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Hairline()
        }
    }
}

/// A row of choices where one is on.
struct Segments<Option: Hashable>: View {
    var options: [Option]
    @Binding var selection: Option
    var title: (Option) -> String
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 12.5))
                        .foregroundStyle(selection == option ? Theme.ink : Theme.secondary)
                        .padding(.horizontal, 12).frame(height: 26)
                        .background {
                            if selection == option {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.cardHover)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
        .fixedSize()
        .animation(Motion.glide, value: selection)
    }
}

/// A thin slider that doesn't look like the system's.
struct ThinSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geometry in
            let span = max(range.upperBound - range.lowerBound, 0.001)
            let fraction = (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line).frame(height: 3)
                Capsule().fill(tint).frame(width: max(geometry.size.width * fraction, 3), height: 3)
                Circle().fill(Theme.ink).frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .offset(x: (geometry.size.width - 13) * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let raw = min(max(drag.location.x / max(geometry.size.width, 1), 0), 1) * span + range.lowerBound
                value = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
            })
        }
        .frame(height: 18)
    }
}

/// A small box for a number, with a unit after it. Typing commits on Return or on leaving the field.
struct NumberBox: View {
    @Binding var value: Double
    var unit: String
    var range: ClosedRange<Double>
    var width: CGFloat = 46
    var decimals = 0

    @State private var text = ""
    @FocusState private var focused: Bool

    private func show(_ value: Double) -> String { String(format: "%.\(decimals)f", value) }

    private func commit() {
        guard let number = Double(text.replacingOccurrences(of: ",", with: ".")) else {
            text = show(value)
            return
        }
        let clamped = min(max(number, range.lowerBound), range.upperBound)
        value = clamped
        text = show(clamped)
    }

    var body: some View {
        HStack(spacing: 3) {
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13)).monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .focused($focused)
                .onSubmit(commit)
            Text(unit).font(.system(size: 12)).foregroundStyle(Theme.tertiary).fixedSize()
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(focused ? Theme.accent.opacity(0.6) : Theme.line))
        .onAppear { text = show(value) }
        .onChange(of: value) { if !focused { text = show(value) } }
        .onChange(of: focused) { if !focused { commit() } }
    }
}

/// A rounded text field on the field colour.
struct SoftField: View {
    var title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .overlay(alignment: .leading) {
                if text.isEmpty {
                    Text(title).font(.system(size: 13)).foregroundStyle(Theme.tertiary).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 11).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line))
    }
}

/// A name that reads as a label until you ask to change it. Return or clicking away keeps what was
/// typed, Esc leaves it as it was. An empty name is passed on, for the caller to decide about.
struct RenameField: View {
    var current: String
    var placeholder: String
    var save: (String) -> Void
    var close: () -> Void

    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    private func finish(keeping: Bool) {
        guard !finished else { return }
        finished = true
        if keeping { save(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        close()
    }

    var body: some View {
        SoftField(placeholder, text: $text)
            .focused($focused)
            .onSubmit { finish(keeping: true) }
            .onExitCommand { finish(keeping: false) }
            .onAppear {
                text = current
                DispatchQueue.main.async { focused = true }
            }
            .onChange(of: focused) { was, now in
                if was, !now { finish(keeping: true) }
            }
    }
}

/// macOS gives a window's first text field the keyboard as soon as the window shows, so a page would
/// open with a blinking caret in a field nobody asked to edit. Only a click should put one there.
struct FocusReset: NSViewRepresentable {
    var page: Page

    func makeNSView(context: Context) -> Holder { Holder() }
    func updateNSView(_ view: Holder, context: Context) { view.page = page }

    final class Holder: NSView {
        private var observer: NSObjectProtocol?

        var page: Page? {
            didSet { if oldValue != nil, oldValue != page { clear() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            clear()
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.clear()
                    if let observer = self?.observer { NotificationCenter.default.removeObserver(observer) }
                    self?.observer = nil
                }
            }
        }

        private func clear() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let window = self?.window, window.firstResponder is NSText else { return }
                window.makeFirstResponder(nil)
            }
        }
    }
}

/// Where the title bar would be: dragging moves the window, a double-click zooms it.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}
