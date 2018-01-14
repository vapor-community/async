#if os(macOS)

import Darwin

internal enum KqueueEventSourceType {
    case read
    case write
    case timer(timeout: Int)
}

/// Kqueue based `EventSource` implementation.
public final class KqueueEventSource: EventSource {
    /// See EventSource.state
    public private(set) var state: EventSourceState

    /// The underlying `kevent`.
    private var event: kevent

    /// This event's `kqueue` handle.
    private let kq: Int32

    /// The callback to signal.
    private var callback: EventCallback

    /// Pointer to this event source to store on kevent
    private var pointer: UnsafeMutablePointer<KqueueEventSource>

    /// Create a new `KqueueEventSource` for the supplied descriptor.
    internal init(
        descriptor: Int32,
        kq: Int32,
        type: KqueueEventSourceType,
        callback: @escaping EventCallback
    ) {
        var event = kevent()
        switch type {
        case .read:
            event.filter = Int16(EVFILT_READ)
        case .write:
            event.filter = Int16(EVFILT_WRITE)
        case .timer(let timeout):
            event.filter = Int16(EVFILT_TIMER)
            event.data = timeout
        }
        event.ident = UInt(dup(descriptor))

        let pointer = UnsafeMutablePointer<KqueueEventSource>.allocate(capacity: 1)
        event.udata = UnsafeMutableRawPointer(pointer)

        self.state = .suspended
        self.pointer = pointer
        self.event = event
        self.callback = callback
        self.kq = kq

        pointer.initialize(to: self)
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
            state = .suspended
            update()
        }
    }

    /// See EventSource.resume
    public func resume() {
        switch state {
        case .cancelled:
            fatalError("Called `.resume()` on a cancelled KqueueEventSource.")
        case .suspended:
            event.flags = UInt16(EV_ADD | EV_ENABLE)
            state = .resumed
            update()
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
            update()

            // deallocate reference to self
            pointer.deinitialize()
            pointer.deallocate(capacity: 1)
        }
    }

    /// Signals the event's callback.
    internal func signal(_ eof: Bool) {
        switch state {
        case .resumed:
            callback(eof)
        case .cancelled, .suspended: break
        }
    }


    /// Updates the `kevent` to the `kqueue` handle.
    private func update() {
        let response = kevent(kq, &event, 1, nil, 0, nil)
        if response < 0 {
            let reason = String(cString: strerror(errno))
            fatalError("An error occured during KqueueEventSource.update: \(reason)")
        }
    }
}

#endif
