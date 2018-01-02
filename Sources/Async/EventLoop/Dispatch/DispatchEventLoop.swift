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

    /// See EventLoop.async
    public func async(_ callback: @escaping EventLoop.AsyncCallback) {
        queue.async { callback() }
    }

    /// See EventLoop.run
    public func run() {
        // From the documentation of RunLoop.run():
        // "If no input sources or timers are attached to the run loop, this method exits immediately."

        // To avoid this, the following block creates a pending timer far into the future to keep the run loop
        // alive until sockets are connected.
        if #available(OSX 10.12, *) {
            // New syntax for macOS 10.12+ and Linux
            _ = Timer.scheduledTimer(withTimeInterval: TimeInterval.greatestFiniteMagnitude,
                                     repeats: true,
                                     block: { _ in })
        } else {
            // Fallback on earlier macOS versions
            #if os(macOS)
            _ = Timer.scheduledTimer(timeInterval: TimeInterval.greatestFiniteMagnitude,
                                     target: self,
                                     selector: #selector(keepAlive),
                                     userInfo: nil,
                                     repeats: true)
            #endif
        }

        RunLoop.current.run()
    }

    @objc private func keepAlive() {
    }
}
