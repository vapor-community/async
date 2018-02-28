#if os(macOS)

import Darwin

internal enum KqueueEventSourceType {
    case read
    case write
    case timer(timeout: EventLoopTimeout)
    case nextTick
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
    private var pointer: UnsafeMutablePointer<KqueueEventSource?>

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
            event.data = timeout.milliseconds
        case .nextTick:
            event.filter = EVFILT_USER
            event.flags = EV_ONESHOT
            event.fflags = NOTE_TRIGGER | NOTE_FFCOPY
        }
        event.ident = UInt(bitPattern: Int(descriptor))

        let pointer = UnsafeMutablePointer<KqueueEventSource?>.allocate(capacity: 1)
        event.udata = UnsafeMutableRawPointer(pointer)

        self.state = .suspended
        self.pointer = pointer
        self.event = event
        self.callback = callback
        self.kq = kq

        pointer.initialize(to: self)
        DEBUG("KqueueEventSource.init() [\(event)]")
    }

    /// See EventSource.suspend
    public func suspend() {
        DEBUG("KqueueEventSource.suspend() [\(event)]")
        switch state {
        case .cancelled:
            ERROR("Called `.suspend()` on a cancelled KqueueEventSource.")
        case .suspended:
            ERROR("Called `.suspend()` on a suspended KqueueEventSource.")
        case .resumed:
            event.flags = EV_ADD | EV_DISABLE
            state = .suspended
            update()
        }
    }

    /// See EventSource.resume
    public func resume() {
        DEBUG("KqueueEventSource.resume() [\(event)]")
        switch state {
        case .cancelled:
            ERROR("Called `.resume()` on a cancelled KqueueEventSource.")
        case .suspended:
            if event.flags & EV_ONESHOT > 0 {
                event.flags = EV_ADD | EV_ENABLE | EV_ONESHOT
                state = .resumed
                update()
            } else {
                event.flags = EV_ADD | EV_ENABLE
                state = .resumed
                update()
            }
        case .resumed:
            ERROR("Called `.resume()` on a resumed KqueueEventSource.")
        }
    }

    /// See EventSource.cancel
    public func cancel() {
        DEBUG("KqueueEventSource.cancel() [\(event)]")
        switch state {
        case .cancelled: ERROR("Called `.cancel()` on a cancelled KqueueEventSource.")
        case .resumed, .suspended:
            event.flags = EV_DELETE
            state = .cancelled
            update()
            pointer.pointee = nil
        }
    }

    /// Signals the event's callback.
    internal func signal(_ eof: Bool) {
        DEBUG("KqueueEventSource.signal(\(eof)) [\(event)]")
        switch state {
        case .resumed:
            if event.flags & EV_ONESHOT > 0 {
                callback(true)
            } else {
                callback(eof)
            }
        case .cancelled, .suspended: break
        }
    }


    /// Updates the `kevent` to the `kqueue` handle.
    private func update() {
        var response = kevent(kq, &event, 1, nil, 0, nil)
        if event.fflags & NOTE_TRIGGER > 0 {
            response = kevent(kq, &event, 1, nil, 0, nil)
        }
        if response < 0 {
            let reason = String(cString: strerror(errno))
            switch errno {
            case ENOENT: break // event has already been deleted
            default: ERROR("An error occured during KqueueEventSource.update: \(reason)")
            }
        }
    }

    deinit {
        // deallocate reference to self
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}

let EVFILT_READ = Int16(Darwin.EVFILT_READ)
let EVFILT_WRITE = Int16(Darwin.EVFILT_WRITE)
let EVFILT_TIMER = Int16(Darwin.EVFILT_TIMER)
let EVFILT_USER = Int16(Darwin.EVFILT_USER)

let EV_ADD = UInt16(Darwin.EV_ADD)
let EV_ENABLE = UInt16(Darwin.EV_ENABLE)
let EV_DISABLE = UInt16(Darwin.EV_DISABLE)
let EV_DELETE = UInt16(Darwin.EV_DELETE)
let EV_EOF = UInt16(Darwin.EV_EOF)
let EV_ERROR = UInt16(Darwin.EV_ERROR)
let EV_ONESHOT = UInt16(Darwin.EV_ONESHOT)

let NOTE_TRIGGER = UInt32(bitPattern: Darwin.NOTE_TRIGGER)
let NOTE_FFCOPY = Darwin.NOTE_FFCOPY

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
        if self.filter == EVFILT_READ {
            flags.append("EVFILT_READ")
        }
        if self.filter == EVFILT_WRITE {
            flags.append("EVFILT_WRITE")
        }
        if self.filter == EVFILT_USER {
            flags.append("EVFILT_USER")
        }
        if self.fflags & NOTE_TRIGGER > 0 {
            flags.append("NOTE_TRIGGER")
        }
        if self.fflags & NOTE_FFCOPY > 0 {
            flags.append("NOTE_FFCOPY")
        }
        return "kevent#\(ident) \(flags.joined(separator: "|"))"
    }
}

#endif

/// For printing debug info.
func DEBUG(_ string: @autoclosure () -> String, file: StaticString = #file, line: Int = #line) {
    #if VERBOSE
    print("[VERBOSE] \(string()) [\(file.description.split(separator: "/").last!):\(line)]")
    #endif
}
