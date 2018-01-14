import Foundation

#if os(Linux)
    public typealias DefaultEventLoop = EpollEventLoop
#endif

#if os(macOS)
    public typealias DefaultEventLoop = KqueueEventLoop
#endif


/// An event callback.
/// If the supplied argument is true, this event
/// has been cancelled and the callback will never
/// be called again.
public typealias EventCallback = (Bool) -> ()

/// An event loop handles signaling completion of blocking work
/// to create non-blocking, callback-based pipelines.
public protocol EventLoop: Worker {
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

    /// Creates a new timer event source.
    /// This callback will be called perodically when the timeout is reached.
    func onTimeout(milliseconds: Int, _ callback: @escaping EventCallback) -> EventSource

    /// Runs a single cycle for this event loop.
    /// Call `EventLoop.runLoop()` to run indefinitely.
    func run()
}

extension EventLoop {
    /// Returns the current event loop.
    public static var current: EventLoop {
        guard let eventLoop = Thread.current.threadDictionary["eventLoop"] as? EventLoop else {
            // fatalError("Current thread is not an event loop.")
            return try! DefaultEventLoop(label: "N/A")
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
        // print("[\(label)] Booting")
        while true { run() }
    }
}

extension Thread {
    public static func async(_ work: @escaping () -> ()) {
        if #available(OSX 10.12, *) {
            Thread.detachNewThread {
                work()
            }
        } else {
            fatalError()
        }
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
