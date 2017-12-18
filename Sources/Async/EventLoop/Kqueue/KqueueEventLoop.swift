#if os(macOS)

import Darwin
import Foundation

/// Kqueue based `EventLoop` implementation.
public final class KqueueEventLoop: EventLoop {
    /// See EventLoop.Source
    public typealias Source = KqueueEventSource

    /// See EventLoop.label
    public let label: String

    /// The `kqueue` handle.
    private let kq: Int32

    /// Event list buffer. This will be passed to
    /// kevent each time the event loop is ready for
    /// additional signals.
    private var eventlist: UnsafeMutableBufferPointer<kevent>

    /// Read source buffer.
    private var readSources: UnsafeMutableBufferPointer<KqueueEventSource?>

    /// Write source buffer.
    private var writeSources: UnsafeMutableBufferPointer<KqueueEventSource?>

    /// Async tasks to run
    private var tasks: [AsyncCallback]

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

        /// no descriptor should be larger than this number
        let maxDescriptor = 4096
        readSources = .init(start: .allocate(capacity: maxDescriptor), count: maxDescriptor)
        writeSources = .init(start: .allocate(capacity: maxDescriptor), count: maxDescriptor)

        tasks = []
    }

    /// See EventLoop.onReadable
    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        let source = KqueueEventSource(descriptor: descriptor, kq: kq, callback: callback)
        source.event.filter = Int16(EVFILT_READ)
        readSources[Int(descriptor)] = source
        return source
    }

    /// See EventLoop.onWritable
    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> EventSource {
        let source = KqueueEventSource(descriptor: descriptor, kq: kq, callback: callback)
        source.event.filter = Int16(EVFILT_WRITE)
        writeSources[Int(descriptor)] = source
        return source
    }

    /// See EventLoop.async
    public func async(_ callback: @escaping EventLoop.AsyncCallback) {
        tasks.append(callback)
    }

    /// See EventLoop.run
    public func run() {
        // run all async tasks
        if self.tasks.count > 0 {
            let tasks = self.tasks
            self.tasks = []
            for task in tasks {
                task()
            }
        }

        var timeout = timespec()
        timeout.tv_sec = 0
        timeout.tv_nsec = 100_000_000 // 0.1 seconds

        // check for new events
        let eventCount = kevent(kq, nil, 0, eventlist.baseAddress, Int32(eventlist.count), &timeout)
        guard eventCount >= 0 else {
            print("An error occured while running kevent: \(eventCount).")
            return
        }

        /// print("[\(label)] \(eventCount) New Events")
        events: for i in 0..<Int(eventCount) {
            let event = eventlist[i]

            let ident = Int(event.ident)
            let source: KqueueEventSource
            switch Int32(event.filter) {
            case EVFILT_READ: source = readSources[ident]!
            case EVFILT_WRITE: source = writeSources[ident]!
            default: fatalError()
            }

            if event.flags & UInt16(EV_ERROR) > 0 {
                let reason = String(cString: strerror(Int32(event.data)))
                print("An error occured during an event: \(reason)")
            } else if event.flags & UInt16(EV_EOF) > 0 {
                source.signal(true)
                switch Int32(event.filter) {
                case EVFILT_READ: readSources[ident] = nil
                case EVFILT_WRITE: writeSources[ident] = nil
                default: fatalError()
                }
            } else {
                source.signal(false)
            }
        }
    }

    deinit {
        eventlist.baseAddress?.deallocate(capacity: eventlist.count)
        readSources.baseAddress?.deallocate(capacity: readSources.count)
        writeSources.baseAddress?.deallocate(capacity: writeSources.count)
    }
}

#endif
