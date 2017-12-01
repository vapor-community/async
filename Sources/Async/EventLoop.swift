import Dispatch

/// An event loop with context.
public protocol EventLoop {
    /// This worker's event loop
    var queue: DispatchQueue { get }
}

extension DispatchQueue: EventLoop {
    /// See EventLoop.queue
    public var queue: DispatchQueue {
        return self
    }
}

// MARK: Default

extension EventLoop {
    /// The default event loop
    public static var `default`: EventLoop { return DispatchQueue.global() }
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
