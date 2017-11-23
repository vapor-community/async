import Dispatch

/// An event loop with context.
public final class EventLoop: Extendable {
    /// This worker's event loop
    public let queue: DispatchQueue

    /// Allows the worker to be extended
    public var extend: Extend

    /// Create a new worker.
    public init(queue: DispatchQueue) {
        self.queue = queue
        self.extend = Extend()
    }
}

// MARK: Default
private let _default = EventLoop(queue: .global())

extension EventLoop {
    /// The default event loop
    public static var `default`: EventLoop { return _default }
}

#if os(macOS)

extension EventLoop {
    /// Returns the name of the current event loop.
    /// Useful for debugging.
    public static var currentName: String {
        let name = __dispatch_queue_get_label(nil)
        return String(cString: name, encoding: .utf8)!
    }
}

#endif
