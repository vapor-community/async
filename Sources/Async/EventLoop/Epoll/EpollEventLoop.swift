#if os(Linux)

import Glibc
import CEpoll

/// Epoll based `EventLoop` implementation.
public final class EpollEventLoop: EventLoop {
    /// See EventLoop.label
    public var label: String

    /// The epoll handle.
    private let epfd: Int32

    /// Async task to run
    private var task: AsyncCallback?

    /// Event list buffer. This will be passed to
    /// kevent each time the event loop is ready for
    /// additional signals.
    private var eventlist: UnsafeMutableBufferPointer<epoll_event>

    /// Create a new `EpollEventLoop`
    public init(label: String) throws {
        self.label = label
        let status = epoll_create1(0)
        if status == -1 {
            throw EventLoopError(identifier: "epoll_create1", reason: "Could not create epoll queue.")
        }
        self.epfd = status

        /// the maxiumum amount of events to handle per cycle
        let maxEvents = 4096
        eventlist = .init(start: .allocate(capacity: maxEvents), count: maxEvents)

        /// set current task to nil
        task = nil
    }

    /// See EventLoop.onReadable
    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        return EpollEventSource(
            epfd: epfd,
            type: .read(descriptor: descriptor),
            callback: callback
        )
    }

    /// See EventLoop.onWritable
    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        return EpollEventSource(
            epfd: epfd,
            type: .write(descriptor: descriptor),
            callback: callback
        )
    }

    /// See EventLoop.ononTimeout
    public func onTimeout(timeout: Int, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        print("\(#function)")
        return EpollEventSource(
            epfd: epfd,
            type: .timer(timeout: timeout),
            callback: callback
        )
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
        let eventCount = epoll_wait(epfd, eventlist.baseAddress, Int32(eventlist.count), -1)
        guard eventCount >= 0 else {
            print("An error occured while running kevent: \(eventCount).")
            return
        }

        /// print("[\(label)] \(eventCount) New Events")
        events: for i in 0..<Int(eventCount) {
            let event = eventlist[i]
            let source = event.data.ptr.assumingMemoryBound(to: EpollEventSource.self).pointee

            if event.events & EPOLLERR.rawValue > 0 {
                let reason = String(cString: strerror(Int32(event.data.u32)))
                print("An error occured during an event: \(reason)")
            } else {
                source.signal(event.events & EPOLLHUP.rawValue > 0)
            }
        }
    }
}

#endif
