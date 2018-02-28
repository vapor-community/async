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
    func onTimeout(timeout: EventLoopTimeout, _ callback: @escaping EventCallback) -> EventSource

    /// Creates a new one-shot event source.
    /// This callback will be called once on the next tick of the event loop.
    func onNextTick(_ callback: @escaping EventCallback) -> EventSource

    /// Runs a single cycle for this event loop.
    /// Call `EventLoop.runLoop()` to run indefinitely.
    func run(timeout: EventLoopTimeout?)

    /// Runs the EventLoop forever.
    func runLoop(timeout: EventLoopTimeout?)
}

extension EventLoop {
    /// See Worker.eventLoop
    public var eventLoop: EventLoop {
        return self
    }

    /// Calls `.run(timeout:)` with `nil` timeout.
    public func run() {
        self.run(timeout: nil)
    }

    /// Calls `.runLoop(timeout:)` with `nil` timeout.
    public func runLoop() {
        self.runLoop(timeout: nil)
    }
}

extension Worker {
    /// Performs blocking work on separate thread.
    /// The returned Future will be completed (on the EventLoop)
    /// when the work has finished.
    public func doBlockingWork<T>(_ blockingWork: @escaping () -> (T)) -> Future<T> {
        let promise = Promise(T.self)
        Thread.async {
            promise.complete(blockingWork(), onNextTick: self)
        }
        return promise.future
    }
}

extension Thread {
    public static func async(_ work: @escaping () -> ()) {
        if #available(OSX 10.12, *) {
            Thread.detachNewThread {
                work()
            }
        } else {
            ERROR("Thead.async requires macOS 10.12 or greater")
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
