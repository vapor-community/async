import Dispatch
import Foundation

/// Dispatch based `EventLoop` implementation.
public final class DispatchEventLoop: EventLoop {
    /// See EventLoop.Source
    public typealias Source = DispatchEventSource

    /// See EventLoop.label
    public var label: String {
        return queue.label
    }

    /// The internal dispatch queue powering this event loop.
    private let queue: DispatchQueue

    /// Create a new `DispatchEventLoop`.
    public init(label: String) {
        queue = DispatchQueue(label: label)
    }

    /// See EventLoop.onReadable
    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { callback(false) }
        source.setCancelHandler { callback(true) }
        return DispatchEventSource(source: source)
    }

    /// See EventLoop.onWritable
    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { callback(false) }
        source.setCancelHandler { callback(true) }
        return DispatchEventSource(source: source)
    }

    /// See EventLoop.run
    public func run() {
        /// FIXME: this run is a `-> Never` which will
        /// only work correctly if `run()` or `runLoop()` is called only once.
        RunLoop.main.run()
    }
}
