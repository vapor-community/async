import Darwin

/// Kqueue based `EventSource` implementation.
public final class KqueueEventSource: EventSource {
    /// See EventSource.state
    public var state: EventSourceState

    /// The underlying `kevent`.
    internal var event: kevent

    /// This event's `kqueue` handle.
    private let kq: Int32

    /// The callback to signal.
    private var callback: EventLoop.EventCallback

    /// Create a new `KqueueEventSource` for the supplied descriptor.
    internal init(descriptor: Int32, kq: Int32, callback: @escaping EventLoop.EventCallback) {
        self.callback = callback
        state = .suspended
        self.kq = kq
        var event = kevent()
        event.ident = UInt(descriptor)
        event.flags = UInt16(EV_ADD | EV_DISABLE)
        event.fflags = 0
        event.data = 0
        self.event = event
    }

    /// See EventSource.suspend
    public func suspend() {
        switch state {
        case .cancelled:
            fatalError("Called `.suspend()` on a cancelled KqueueEventSource.")
        case .suspended:
            fatalError("Called `.suspend()` on a suspended KqueueEventSource.")
        case .resumed:
            event.flags = UInt16(EV_ADD | EV_DISABLE)
            update()
            state = .suspended
        }
    }

    /// See EventSource.resume
    public func resume() {
        switch state {
        case .cancelled:
            fatalError("Called `.resume()` on a cancelled KqueueEventSource.")
        case .suspended:
            event.flags = UInt16(EV_ADD | EV_ENABLE)
            update()
            state = .resumed
        case .resumed:
            fatalError("Called `.resume()` on a resumed KqueueEventSource.")
        }
    }

    /// See EventSource.cancel
    public func cancel() {
        switch state {
        case .cancelled: fatalError("Called `.cancel()` on a cancelled KqueueEventSource.")
        case .resumed, .suspended:
            event.flags = UInt16(EV_DELETE)
            state = .cancelled
        }
    }

    /// Signals the event's callback.
    internal func signal(_ eof: Bool) {
        switch state {
        case .resumed:
            if eof {
                state = .cancelled
            }
            callback(eof)
        case .cancelled, .suspended: break
        }
    }


    /// Updates the `kevent` to the `kqueue` handle.
    private func update() {
        switch state {
        case .cancelled: break
        case .resumed, .suspended:
            let response = kevent(kq, &event, 1, nil, 0, nil)
            if response < 0 {
                let reason = String(cString: strerror(errno))
                print("An error occured during KqueueEventSource.update: \(reason)")
            }
        }
    }
}
