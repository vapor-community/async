#if os(macOS)

import Darwin
import Foundation

/// Kqueue based `EventLoop` implementation.
public final class KqueueEventLoop: EventLoop {
    /// See EventLoop.label
    public let label: String

    /// The `kqueue` handle for write signals.
    private let kq: Int32

    /// Current stored unique file descriptor.
    private var _ufd: Int32

    /// Returns the next valid file descriptor.
    /// Note: This will wrap back to -1 at some point.
    private var ufd: Int32 {
        get {
            defer {
                _ufd = _ufd &- 1
                if _ufd >= 0 {
                    _ufd = -1
                }
            }
            return _ufd
        }
    }

    /// Current run depth.
    private var depth: Int

    /// Event list buffer. This will be passed to
    /// kevent each time the event loop is ready for
    /// additional signals.
    private var eventlist: UnsafeMutableBufferPointer<kevent>
    
    /// Create a new `KqueueEventLoop`
    public init(label: String) throws {
        self.label = label
        self.kq = try KqueueEventLoop.makekq()
        self._ufd = -1
        self.depth = 0

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
    public func onTimeout(timeout: EventLoopTimeout, _ callback: @escaping EventCallback) -> EventSource {
        return KqueueEventSource(descriptor: ufd, kq: kq, type: .timer(timeout: timeout), callback: callback)
    }

    /// See EventLoop.onTick
    public func onNextTick(_ callback: @escaping EventCallback) -> EventSource {
        return KqueueEventSource(descriptor: ufd, kq: kq, type: .nextTick, callback: callback)
    }

    /// See EventLoop.run
    public func run(timeout: EventLoopTimeout?) {
        DEBUG("KqueueEventLoop.run(timeout: \(timeout?.milliseconds.description ?? "nil")) [depth: \(depth)]")
        // increment run depth
        depth += 1
        let startDepth = depth

        // check for new events
        let eventCount: Int32
        if let timeout = timeout {
            var t = timespec(tv_sec: 0, tv_nsec: timeout.nanoseconds)
            eventCount = kevent(kq, nil, 0, eventlist.baseAddress, Int32(eventlist.count), &t)
        } else {
            eventCount = kevent(kq, nil, 0, eventlist.baseAddress, Int32(eventlist.count), nil)
        }
        guard eventCount >= 0 else {
            switch errno {
            case EINTR:
                run(timeout: timeout) // run again
                return
            default:
                let reason = String(cString: strerror(Int32(errno)))
                ERROR("An error occured while running kevent: \(reason).")
                return
            }
        }

        // signal the events
        events: for i in 0..<Int(eventCount) {
            // verify depth hasn't increased since last run
            guard depth == startDepth else {
                break events
            }

            let event = eventlist[i]
            guard let source = event.udata.assumingMemoryBound(to: KqueueEventSource?.self).pointee else {
                // source has been cancelled
                return
            }
            
            if event.flags & EV_ERROR > 0 {
                let reason = String(cString: strerror(Int32(event.data)))
                ERROR("[Async] An error occured during an event: \(reason).")
            } else {
                source.signal(event.flags & EV_EOF > 0)
            }
        }
    }

    /// See EventLoop.runLoop
    public func runLoop(timeout: EventLoopTimeout?) {
        DEBUG("KqueueEventLoop.runLoop(timeout: \(timeout?.milliseconds.description ?? "nil"))")
        while true {
            self.depth = 0
            self.run(timeout: timeout)
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

func ERROR(_ string: String, file: StaticString = #file, line: Int = #line) {
    print("[Async] \(string) [\(file):\(line)]")
}
