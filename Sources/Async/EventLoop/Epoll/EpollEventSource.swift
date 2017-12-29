#if os(Linux)

import Glibc
import CEpoll

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

#endif
