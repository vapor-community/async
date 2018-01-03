#if os(Linux)

import Glibc
import CEpoll

internal enum EpollEventSourceType {
    case read(descriptor: Int32)
    case write(descriptor: Int32)
    case timer(timeout: Int)
}

public final class EpollEventSource: EventSource {
    /// See EventSource.state
    public var state: EventSourceState

    /// This event's epoll handle.
    private let epfd: Int32

    /// The underlying `epoll_event`
    internal var event: epoll_event

    /// The callback to signal.
    private var callback: EventLoop.EventCallback

    /// Pointer to this event source to store on epoll event
    private var pointer: UnsafeMutablePointer<EpollEventSource>

    /// This source's type
    private let type: EpollEventSourceType

    /// Create a new `EpollEventSource` for the supplied descriptor.
    internal init(
        epfd: Int32,
        type: EpollEventSourceType,
        callback: @escaping EventLoop.EventCallback
    ) {
        print("\(#function)")
        var event = epoll_event()
        switch type {
        case .read(let descriptor):
            event.data.fd = descriptor
            event.events = EPOLLET.rawValue | EPOLLIN.rawValue
        case .write(let descriptor):
            event.data.fd = descriptor
            event.events = EPOLLET.rawValue | EPOLLOUT.rawValue
        case .timer(let timeout):
            let tfd = timerfd_create(CLOCK_MONOTONIC, 0)
            if tfd == -1 {
                fatalError("timerfd_create() failed: errno=\(errno)")
            }

            var ts = itimerspec()
            ts.it_interval.tv_sec = 0
            ts.it_interval.tv_nsec = 0
            ts.it_value.tv_sec = timeout / 1000
            ts.it_value.tv_nsec = (timeout % 1000) * 1000000

            if timerfd_settime(tfd, 0, &ts, nil) < 0 {
                close(tfd);
                fatalError("timerfd_settime() failed: errno=\(errno)")
            }

            event.data.fd = tfd
            event.events = EPOLLIN.rawValue
        }

        let pointer = UnsafeMutablePointer<EpollEventSource>.allocate(capacity: 1)
        event.data.ptr = UnsafeMutableRawPointer(pointer)

        self.type = type
        self.pointer = pointer
        self.callback = callback
        state = .suspended
        self.epfd = epfd
        self.event = event
    }

    /// See EventSource.suspend
    public func suspend() {
        print("\(#function)")
        switch state {
        case .cancelled:
            fatalError("Called `.suspend()` on a cancelled EpollEventSource.")
        case .suspended:
            fatalError("Called `.suspend()` on a suspended EpollEventSource.")
        case .resumed:
            update(op: EPOLL_CTL_DEL)
        }
    }

    /// See EventSource.resume
    public func resume() {
        print("\(#function)")
        switch state {
        case .cancelled:
            fatalError("Called `.resume()` on a cancelled EpollEventSource.")
        case .suspended:
            update(op: EPOLL_CTL_ADD)
        case .resumed:
            fatalError("Called `.resume()` on a resumed EpollEventSource.")
        }
    }

    /// See EventSource.cancel
    public func cancel() {
        print("\(#function)")
        switch state {
        case .cancelled: fatalError("Called `.cancel()` on a cancelled EpollEventSource.")
        case .resumed, .suspended:
            update(op: EPOLL_CTL_DEL)
            // deallocate reference to self
            pointer.deallocate(capacity: 1)
            pointer.deinitialize()

            switch type {
            case .timer: close(event.data.fd)
            default: break
            }
        }
    }

    internal func signal(_ eof: Bool) {
        callback(eof)
    }

    /// Updates the `epoll_event` to the efd handle.
    private func update(op: Int32) {
        print("\(#function)")
        let response = epoll_ctl(epfd, op, event.data.fd, &event);
        if response < 0 {
            let reason = String(cString: strerror(errno))
            print("An error occured during EpollEventSource.update: \(reason)")
        }
    }

    deinit {
        print("\(#function)")
//        switch state {
//        case .resumed, .suspended: cancel()
//        default: break
//        }
    }
}

#endif
