#if os(Linux)

import Glibc
import CEpoll

//internal enum EpollEventSourceType {
//    case read
//    case write
//}

public final class EpollEventSource: EventSource {
    /// See EventSource.state
    public var state: EventSourceState

    /// This event's epoll handle.
    private let epfd: Int32

    /// The underlying `epoll_event`
    internal var event: epoll_event

    /// The callback to signal.
    private var callback: EventLoop.EventCallback

    /// Create a new `EpollEventSource` for the supplied descriptor.
    internal init(descriptor: Int32, epfd: Int32, callback: @escaping EventLoop.EventCallback) {
        self.callback = callback
        state = .suspended
        self.epfd = epfd
        var event = epoll_event()
        event.data.fd = descriptor
        event.events = EPOLLET.rawValue
        self.event = event
    }

    /// See EventSource.suspend
    public func suspend() {
        update(op: EPOLL_CTL_DEL)
    }

    /// See EventSource.resume
    public func resume() {
        update(op: EPOLL_CTL_ADD)
    }

    /// See EventSource.cancel
    public func cancel() {
        update(op: EPOLL_CTL_DEL)
    }

    internal func signal(_ eof: Bool) {
        callback(eof)
    }

    /// Updates the `epoll_event` to the efd handle.
    private func update(op: Int32) {
        switch state {
        case .cancelled: break
        case .resumed, .suspended:
            let response = epoll_ctl(epfd, op, event.data.fd, &event);
            if response < 0 {
                let reason = String(cString: strerror(errno))
                print("An error occured during EpollEventSource.update: \(reason)")
            }
        }
    }

}

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

    /// Read source buffer.
    private var readSources: UnsafeMutableBufferPointer<EpollEventSource?>

    /// Write source buffer.
    private var writeSources: UnsafeMutableBufferPointer<EpollEventSource?>

    /// Create a new `EpollEventLoop`
    public init(label: String) throws {
        self.label = label
        let status = epoll_create1 (0);()
        if status == -1 {
            throw EventLoopError(identifier: "kqueue", reason: "Could not create kqueue.")
        }
        self.epfd = status

        /// the maxiumum amount of events to handle per cycle
        let maxEvents = 4096
        eventlist = .init(start: .allocate(capacity: maxEvents), count: maxEvents)

        /// no descriptor should be larger than this number
        let maxDescriptor = 4096
        readSources = .init(start: .allocate(capacity: maxDescriptor), count: maxDescriptor)
        writeSources = .init(start: .allocate(capacity: maxDescriptor), count: maxDescriptor)
        task = nil
    }

    /// See EventLoop.onReadable
    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        let source = EpollEventSource(descriptor: descriptor, epfd: epfd, callback: callback)
        source.event.events = EPOLLIN.rawValue
        readSources[Int(descriptor)] = source
        return source
    }

    /// See EventLoop.onWritable
    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        let source = EpollEventSource(descriptor: descriptor, epfd: epfd, callback: callback)
        source.event.events = EPOLLOUT.rawValue
        writeSources[Int(descriptor)] = source
        return source
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

            let ident = Int(event.data.fd)
            let source: EpollEventSource

            if event.events & EPOLLOUT.rawValue > 0 {
                source = writeSources[ident]!
            } else if event.events & EPOLLIN.rawValue > 0 {
                source = readSources[ident]!
            } else {
                fatalError("neither epollout or epollin on fetch")
            }

            if event.events & EPOLLERR.rawValue > 0 {
                let reason = String(cString: strerror(Int32(event.data.u32)))
                print("An error occured during an event: \(reason)")
            } else if event.events & EPOLLHUP.rawValue > 0 {
                source.signal(true)

                if event.events & EPOLLOUT.rawValue > 0 {
                    writeSources[ident] = nil
                } else if event.events & EPOLLIN.rawValue > 0 {
                    readSources[ident] = nil
                } else {
                    fatalError("neither epollout or epollin on eof")
                }
            } else {
                source.signal(false)
            }
        }
    }
}

#endif
