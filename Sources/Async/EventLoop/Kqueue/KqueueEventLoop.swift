#if os(macOS)

import Darwin
import Foundation

/// Kqueue based `EventLoop` implementation.
public final class KqueueEventLoop: EventLoop {
    /// See EventLoop.label
    public let label: String

    /// The `kqueue` handle.
    private let kq: Int32

    /// Event list buffer. This will be passed to
    /// kevent each time the event loop is ready for
    /// additional signals.
    private var eventlist: UnsafeMutableBufferPointer<kevent>

    /// Async task to run
    private var task: AsyncCallback?
    
    /// Create a new `KqueueEventLoop`
    public init(label: String) throws {
        self.label = label
        let status = kqueue()
        if status == -1 {
            throw EventLoopError(identifier: "kqueue", reason: "Could not create kqueue.")
        }
        self.kq = status

        /// the maxiumum amount of events to handle per cycle
        let maxEvents = 4096
        eventlist = .init(start: .allocate(capacity: maxEvents), count: maxEvents)

        /// set async task to nil
        task = nil
    }

    /// See EventLoop.onReadable
    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        return KqueueEventSource(descriptor: descriptor, kq: kq, type: .read, callback: callback)
    }

    /// See EventLoop.onWritable
    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        return KqueueEventSource(descriptor: descriptor, kq: kq, type: .write, callback: callback)
    }


    /// See EventLoop.ononTimeout
    public func onTimeout(milliseconds: Int, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        return KqueueEventSource(descriptor: 1, kq: kq, type: .timer(timeout: milliseconds), callback: callback)
    }

    /// See EventLoop.async
    public func async(_ callback: @escaping EventLoop.AsyncCallback) {
        if task != nil {
            // if there is a task waiting, run the event loop
            // until it has been executed
            run()
        }

        /// set the new task
        task = callback
    }
    
    /// See EventLoop.run
    public func run() {
        // while tasks are available, run them
        while let task = self.task {
            // make sure to set this task to nil, so that
            // the task can set a new one if it needs
            self.task = nil

            // run the task, potentially creating a new task
            // in the process
            task()
        }

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

        // print("[\(label)] \(eventCount) New Events")
        events: for i in 0..<Int(eventCount) {
            let event = eventlist[i]
            let source = event.udata.assumingMemoryBound(to: KqueueEventSource.self).pointee
            if event.flags & UInt16(EV_ERROR) > 0 {
                let reason = String(cString: strerror(Int32(event.data)))
                fatalError("An error occured during an event: \(reason)")
            } else {
                source.signal(event.flags & UInt16(EV_EOF) > 0)
            }
        }
    }

    deinit {
        eventlist.baseAddress?.deallocate(capacity: eventlist.count)
    }
}

#endif
