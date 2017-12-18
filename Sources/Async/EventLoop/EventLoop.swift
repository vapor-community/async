import Foundation

/// An event loop handles signaling completion of blocking work
/// to create non-blocking, callback-based pipelines.
public protocol EventLoop: Worker {
    /// An event callback.
    /// If the supplied argument is true, this event
    /// has been cancelled and the callback will never
    /// be called again.
    typealias EventCallback = (Bool) -> ()

    /// An async callback.
    typealias AsyncCallback = () -> ()

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

    /// Sets the closure to be run async.
    func async(_ callback: @escaping AsyncCallback)

    /// Runs a single cycle for this event loop.
    /// Call `EventLoop.runLoop()` to run indefinitely.
    func run()
}

extension EventLoop {
    /// Returns the current event loop.
    public static var current: EventLoop {
        guard let eventLoop = Thread.current.threadDictionary["eventLoop"] as? EventLoop else {
            fatalError("Current thread is not an event loop.")
        }
        return eventLoop
    }

    /// See Worker.eventLoop
    public var eventLoop: EventLoop {
        return self
    }
    /// Calls `.run` indefinitely and sets this event
    /// loop on the current thread.
    public func runLoop() -> Never {
        Thread.current.threadDictionary["eventLoop"] = self
        Thread.current.name = label
        print("[\(label)] Booting")
        while true { run() }
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
