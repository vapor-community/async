/// An event loop handles signaling completion of blocking work
/// to create non-blocking, callback-based pipelines.
public protocol EventLoop: Worker {
    /// An event callback.
    /// If the supplied argument is true, this event
    /// has been cancelled and the callback will never
    /// be called again.
    typealias EventCallback = (Bool) -> ()

    /// This event loop's label.
    var label: String { get }

    /// Creates a new event loop with the supplied label.
    init(label: String) throws

    /// Creates a new on-read event source.
    /// This callback will be called whenever the descriptor
    /// has data ready to read and the event source is resumed.
    func onReadable(descriptor: Int32, _ callback: @escaping EventCallback) -> EventSource

    /// Creates a new on-write event source.
    /// This callback will be called whenever the descriptor
    /// is ready to write data and the event source is resumed.
    func onWritable(descriptor: Int32, _ callback: @escaping EventCallback) -> EventSource

    /// Runs the event loop blocking the current thread.
    /// FIXME: @noreturn / Never (causing warnings in Xcode 9.2)
    func run()
}

extension EventLoop {
    /// See Worker.eventLoop
    public var eventLoop: EventLoop {
        return self
    }
}

/// An error converting types.
public struct EventLoopError: Error {
    /// See Debuggable.reason
    var reason: String
    
    /// See Debuggable.identifier
    var identifier: String
    
    /// Creates a new core error.
    init(identifier: String, reason: String) {
        self.reason = reason
        self.identifier = identifier
    }
}
