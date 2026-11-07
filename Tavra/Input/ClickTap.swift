import CoreGraphics
import Foundation

/// Sees left clicks before apps do, and keeps only the ones a gesture has claimed. Everything else is
/// handed straight on. It runs on its own thread, because a slow tap slows every click on the Mac.
final class ClickTap: @unchecked Sendable {
    private let router: GestureRouter
    private var port: CFMachPort?
    private var loop: CFRunLoop?
    private var source: CFRunLoopSource?

    init(router: GestureRouter) {
        self.router = router
    }

    var isRunning: Bool { port != nil }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<ClickTap>.fromOpaque(info).takeUnretainedValue()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns a tap off if it's slow. Turn it back on, and hold nothing meanwhile.
            tap.router.reset()
            if let port = tap.port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown:
            return tap.router.mouseDown(flags: event.flags.rawValue) ? nil : Unmanaged.passUnretained(event)
        case .leftMouseDragged:
            return tap.router.mouseDragged(flags: event.flags.rawValue) ? nil : Unmanaged.passUnretained(event)
        case .leftMouseUp:
            return tap.router.mouseUp() ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Fails without Accessibility permission.
    func start() -> Bool {
        guard port == nil else { return true }
        let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                           callback: Self.callback, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return false }
        self.port = port
        self.source = source
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Tavra clicks"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let loop { CFRunLoopStop(loop) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil
        loop = nil
        router.reset()
    }
}
