#if os(Linux)

import Glibc
import CEpoll

internal enum EpollEventSourceType {
    case read(descriptor: Int32)
    case write(descriptor: Int32)
    case timer(timeout: EventLoopTimeout)
}

public final class EpollEventSource: EventSource {
    /// See EventSource.state
    public var state: EventSourceState

    /// This event's epoll handle.
    private let epfd: Int32

    /// The underlying `epoll_event`
    internal var event: epoll_event

    /// The callback to signal.
    private var callback: EventCallback

    /// Pointer to this event source to store on epoll event
    private var pointer: UnsafeMutablePointer<EpollEventSource?>

    /// This source's type
    private let type: EpollEventSourceType

    /// This source's descriptor
    let descriptor: Int32

    /// Create a new `EpollEventSource` for the supplied descriptor.
    internal init(
        epfd: Int32,
        type: EpollEventSourceType,
        callback: @escaping EventCallback
    ) {
        let fd: Int32
        var event = epoll_event()
        switch type {
        case .read(let descriptor):
            fd = dup(descriptor)
            event.events = EPOLLIN.rawValue
        case .write(let descriptor):
            fd = dup(descriptor)
            event.events = EPOLLOUT.rawValue
        case .timer(let timeout):
            let tfd = timerfd_create(CLOCK_MONOTONIC, Int32(TFD_NONBLOCK))
            if tfd == -1 {
                fatalError("timerfd_create() failed: errno=\(errno)")
            }

            var ts = itimerspec()
            if timeout.nanoseconds == 0 {
                ts.it_value.tv_nsec = 1
            } else {
                ts.it_value.tv_nsec = timeout.nanoseconds
            }

            if timerfd_settime(tfd, 0, &ts, nil) < 0 {
                // close(tfd);
                ERROR("timerfd_settime() failed: errno=\(errno)")
            }

            fd = tfd
            if timeout.nanoseconds == 0 {
                event.events = EPOLLIN.rawValue | EPOLLONESHOT.rawValue
            } else {
                event.events = EPOLLIN.rawValue
            }
        }

        let pointer = UnsafeMutablePointer<EpollEventSource?>.allocate(capacity: 1)
        event.data.ptr = UnsafeMutableRawPointer(pointer)

        state = .suspended
        self.pointer = pointer
        self.type = type
        self.event = event
        self.callback = callback
        self.epfd = epfd
        self.descriptor = fd

        pointer.initialize(to: self)
    }

    /// See EventSource.suspend
    public func suspend() {
        switch state {
        case .cancelled:
            fatalError("Called `.suspend()` on a cancelled EpollEventSource.")
        case .suspended:
            fatalError("Called `.suspend()` on a suspended EpollEventSource.")
        case .resumed:
            state = .suspended
            update(op: EPOLL_CTL_DEL)
        }
    }

    /// See EventSource.resume
    public func resume() {
        switch state {
        case .cancelled:
            fatalError("Called `.resume()` on a cancelled EpollEventSource.")
        case .suspended:
            state = .resumed
            update(op: EPOLL_CTL_ADD)
        case .resumed:
            fatalError("Called `.resume()` on a resumed EpollEventSource.")
        }
    }

    /// See EventSource.cancel
    public func cancel() {
        switch state {
        case .resumed: self.suspend()
        default: break
        }

        switch state {
        case .cancelled: fatalError("Called `.cancel()` on a cancelled EpollEventSource.")
        case .resumed: fatalError("Called `.cancel()` on a resumed EpollEventSource.")
        case .suspended:
            switch type {
            case .timer: close(event.data.fd)
            default: break
            }

            // deallocate reference to self
            pointer.pointee = nil
        }
    }

    deinit {
        // deallocate reference to self
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
    
    internal func signal(_ eof: Bool) {
        if event.events & EPOLLONESHOT.rawValue > 0 {
            callback(true)
        } else {
            callback(eof)
        }
    }

    /// Updates the `epoll_event` to the efd handle.
    private func update(op: Int32) {
        let ctl = epoll_ctl(epfd, op, descriptor, &event);
        if ctl == -1 {
            let reason = String(cString: strerror(errno))
            ERROR("An error occured during EpollEventSource.update: \(reason)")
        }
    }
}

#endif
