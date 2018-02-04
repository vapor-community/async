#if os(macOS)

import Darwin
import Foundation

/// Kqueue based `EventLoop` implementation.
public final class KqueueEventLoop: EventLoop {
    /// See EventLoop.label
    public let label: String

    /// The `kqueue` handle for write signals.
    private let kq: Int32

    /// Event list buffer. This will be passed to
    /// kevent each time the event loop is ready for
    /// additional signals.
    private var eventlist: UnsafeMutableBufferPointer<kevent>
    
    /// Create a new `KqueueEventLoop`
    public init(label: String) throws {
        self.label = label
        self.kq = try KqueueEventLoop.makekq()

        /// the maxiumum amount of events to handle per cycle
        let maxEvents = 4096
        eventlist = .init(start: .allocate(capacity: maxEvents), count: maxEvents)
    }

    /// See EventLoop.onReadable
    public func onReadable(descriptor: Int32, _ callback: @escaping EventCallback) -> EventSource {
        return KqueueEventSource(descriptor: descriptor, kq: kq, type: .read, callback: callback)
    }

    /// See EventLoop.onWritable
    public func onWritable(descriptor: Int32, _ callback: @escaping EventCallback) -> EventSource {
        return KqueueEventSource(descriptor: descriptor, kq: kq, type: .write, callback: callback)
    }


    /// See EventLoop.onTimeout
    public func onTimeout(milliseconds: Int, _ callback: @escaping EventCallback) -> EventSource {
        return KqueueEventSource(descriptor: 1, kq: kq, type: .timer(timeout: milliseconds), callback: callback)
    }

    /// See EventLoop.run
    public func run() {
        // check for new events
        let eventCount = kevent(kq, nil, 0, eventlist.baseAddress, Int32(eventlist.count), nil)
        guard eventCount >= 0 else {
            switch errno {
            case EINTR:
                run() // run again
                return
            default:
                let reason = String(cString: strerror(Int32(errno)))
                fatalError("An error occured while running kevent: \(reason).")
            }
        }

        // signal the events
        events: for i in 0..<Int(eventCount) {
            let event = eventlist[i]
            guard let source = event.udata.assumingMemoryBound(to: KqueueEventSource?.self).pointee else {
                // source has been cancelled
                return
            }
            if event.flags & EV_ERROR > 0 {
                let reason = String(cString: strerror(Int32(event.data)))
                fatalError("An error occured during an event: \(reason)")
            } else {
                source.signal(event.flags & EV_EOF > 0)
            }
        }
    }

    /// Creates a new `kqueue`.
    private static func makekq() throws -> Int32 {
        let kq = kqueue()
        if kq == -1 {
            throw EventLoopError(identifier: "kqueue", reason: "Could not create read kqueue.")
        }
        return kq
    }

    deinit {
        eventlist.baseAddress?.deallocate()
    }
}

#endif
