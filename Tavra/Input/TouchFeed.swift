import Foundation
import os

/// Reads finger positions from macOS's private multitouch framework. It only ever reads. Apple doesn't
/// document this, so everything is looked up at run time, and if it isn't there Tavra says so.
@MainActor
final class TouchFeed {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias Dimensions = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>) -> Int32
    private typealias IsBuiltIn = @convention(c) (UnsafeMutableRawPointer) -> Bool

    struct Device: Equatable, Sendable {
        var surface: Surface
        var isBuiltIn: Bool
    }

    private static let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let found = dlsym(handle, name) else { return nil }
        return unsafeBitCast(found, to: type)
    }

    /// The callback is a C function with nowhere to keep a reference, so these are global.
    private nonisolated(unsafe) static var router: GestureRouter?
    private static let surfaces = OSAllocatedUnfairLock(initialState: [UInt: Surface]())

    private var list: CFArray?
    private var running: [UnsafeMutableRawPointer] = []
    private(set) var devices: [Device] = []

    var isAvailable: Bool { Self.handle != nil && Self.symbol("MTDeviceCreateList", as: CreateList.self) != nil }

    init(router: GestureRouter) {
        Self.router = router
    }

    /// Layout of MTTouch on current macOS: 96 bytes, identifier at 16, state at 20, normalized
    /// position at 32. Checked against real touches on an M4 Pro.
    private static let stride = 96
    private static let callback: Callback = { device, touches, count, _, _ in
        guard let device, let router = TouchFeed.router else { return 0 }
        let key = UInt(bitPattern: device)
        let surface = TouchFeed.surfaces.withLock { $0[key] } ?? .builtIn
        var fingers: [Finger] = []
        if let touches {
            fingers.reserveCapacity(Int(count))
            for index in 0..<Int(count) {
                let touch = touches.advanced(by: TouchFeed.stride * index)
                let phase = touch.load(fromByteOffset: 20, as: Int32.self)
                // 3 is making contact and 4 is touching. Hovering and lifting don't count.
                guard phase == 3 || phase == 4 else { continue }
                let x = Double(touch.load(fromByteOffset: 32, as: Float.self)), y = Double(touch.load(fromByteOffset: 36, as: Float.self))
                guard (-0.05...1.05).contains(x), (-0.05...1.05).contains(y) else { continue }
                let id = Int64(touch.load(fromByteOffset: 16, as: Int32.self))
                fingers.append(Finger(id: id, x: min(max(x, 0), 1), y: min(max(y, 0), 1)))
            }
        }
        router.touches(fingers, surface: surface)
        return 0
    }

    func start() {
        stop()
        guard let create = Self.symbol("MTDeviceCreateList", as: CreateList.self),
              let register = Self.symbol("MTRegisterContactFrameCallback", as: Register.self),
              let startDevice = Self.symbol("MTDeviceStart", as: Start.self),
              let dimensions = Self.symbol("MTDeviceGetSensorSurfaceDimensions", as: Dimensions.self),
              let array = create()?.takeRetainedValue() else { return }
        list = array
        let builtIn = Self.symbol("MTDeviceIsBuiltIn", as: IsBuiltIn.self)
        var found: [Device] = []
        var map: [UInt: Surface] = [:]
        for object in array as [AnyObject] {
            let device = Unmanaged.passUnretained(object).toOpaque()
            var width: Int32 = 0, height: Int32 = 0
            _ = dimensions(device, &width, &height)
            // In hundredths of a millimetre. Nothing sensible means something other than a trackpad.
            guard width > 1000, height > 1000 else { continue }
            let surface = Surface(widthMM: Double(width) / 100, heightMM: Double(height) / 100)
            map[UInt(bitPattern: device)] = surface
            found.append(Device(surface: surface, isBuiltIn: builtIn?(device) ?? false))
            register(device, Self.callback)
            if startDevice(device, 0) == 0 { running.append(device) }
        }
        let finished = map
        Self.surfaces.withLock { $0 = finished }
        devices = found
    }

    func stop() {
        let stopDevice = Self.symbol("MTDeviceStop", as: Stop.self)
        let unregister = Self.symbol("MTUnregisterContactFrameCallback", as: Register.self)
        for device in running {
            unregister?(device, Self.callback)
            _ = stopDevice?(device)
        }
        running = []
        list = nil
    }

    /// How many are plugged in right now, without disturbing the ones running.
    func count() -> Int {
        guard let create = Self.symbol("MTDeviceCreateList", as: CreateList.self), let array = create()?.takeRetainedValue() else { return 0 }
        return CFArrayGetCount(array)
    }
}
