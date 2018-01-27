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
            event.filter = EVFILT_READ
        case .write:
            event.filter = EVFILT_WRITE
        case .timer(let timeout):
            event.filter = EVFILT_TIMER
            event.data = timeout
        }
        event.ident = UInt(descriptor)

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
            event.flags = EV_ADD | EV_DISABLE
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
            event.flags = EV_ADD | EV_ENABLE
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
            event.flags = EV_DELETE
            state = .cancelled
            update()
            pointer.deinitialize()
        }
    }

    /// Signals the event's callback.
    internal func signal(_ eof: Bool) {
        switch state {
        case .resumed: callback(eof)
        case .cancelled, .suspended: break
        }
    }


    /// Updates the `kevent` to the `kqueue` handle.
    private func update() {
        let response = kevent(kq, &event, 1, nil, 0, nil)
        if response < 0 {
            let reason = String(cString: strerror(errno))
            switch errno {
            case ENOENT: break // event has already been deleted
            case EBADF: break
            default: fatalError("An error occured during KqueueEventSource.update: \(reason)")
            }
        }
    }

    deinit {
        // deallocate reference to self
        pointer.deallocate(capacity: 1)
    }
}

let EVFILT_READ = Int16(Darwin.EVFILT_READ)
let EVFILT_WRITE = Int16(Darwin.EVFILT_WRITE)
let EVFILT_TIMER = Int16(Darwin.EVFILT_TIMER)

let EV_ADD = UInt16(Darwin.EV_ADD)
let EV_ENABLE = UInt16(Darwin.EV_ENABLE)
let EV_DISABLE = UInt16(Darwin.EV_DISABLE)
let EV_DELETE = UInt16(Darwin.EV_DELETE)
let EV_EOF = UInt16(Darwin.EV_EOF)
let EV_ERROR = UInt16(Darwin.EV_ERROR)

extension kevent: CustomStringConvertible {
    public var description: String {
        var flags: [String] = []
        if self.flags & EV_ADD > 0 {
            flags.append("EV_ADD")
        }
        if self.flags & EV_DISABLE > 0 {
            flags.append("EV_DISABLE")
        }
        if self.flags & EV_ENABLE > 0 {
            flags.append("EV_ENABLE")
        }
        if self.flags & EV_DELETE > 0 {
            flags.append("EV_DELETE")
        }
        var filters: [String] = []
        if self.filter == EVFILT_READ {
            filters.append("EVFILT_READ")
        }
        if self.filter == EVFILT_WRITE {
            filters.append("EVFILT_WRITE")
        }
        return "kevent(fd: \(ident) flags: \(flags.joined(separator: "|")) filters: \(filters.joined(separator: "|"))"
    }
}

#endif
