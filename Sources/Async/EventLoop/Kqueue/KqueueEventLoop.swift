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
        eventlist = .allocate(count: maxEvents)

        /// no descriptor should be larger than this number
        let maxDescriptor = 4096
        readSources = .allocate(count: maxDescriptor)
        writeSources = .allocate(count: maxDescriptor)
    }

    /// See EventLoop.onReadable
    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> KqueueEventSource {
        let source = KqueueEventSource(descriptor: descriptor, kq: kq, callback: callback)
        source.event.filter = Int16(EVFILT_READ)
        readSources[Int(descriptor)] = source
        return source
    }

    /// See EventLoop.onWritable
    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> KqueueEventSource {
        let source = KqueueEventSource(descriptor: descriptor, kq: kq, callback: callback)
        source.event.filter = Int16(EVFILT_WRITE)
        writeSources[Int(descriptor)] = source
        return source
    }

    /// See EventLoop.run
    public func run() {
        Thread.current.name = label
        print("[\(label)] Running")
        run: while true {
            let eventCount = kevent(kq, nil, 0, eventlist.baseAddress, Int32(eventlist.count), nil)
            guard eventCount >= 0 else {
                print("An error occured while running kevent: \(eventCount).")
                continue
            }
            /// print("[\(label)] \(eventCount) New Events")
            events: for i in 0..<Int(eventCount) {
                let event = eventlist[i]

                let ident = Int(event.ident)
                let source: KqueueEventSource
                switch Int32(event.filter) {
                case EVFILT_READ:
                    source = readSources[ident]!
                case EVFILT_WRITE:
                    source = writeSources[ident]!
                default: fatalError()
                }

                if event.flags & UInt16(EV_ERROR) > 0 {
                    let reason = String(cString: strerror(Int32(event.data)))
                    print("An error occured during an event: \(reason)")
                } else if event.flags & UInt16(EV_EOF) > 0 {
                    source.signal(true)
                    readSources[ident] = nil
                    writeSources[ident] = nil
                } else {
                    source.signal(false)
                }
            }
        }
    }

    deinit {
        eventlist.deallocate()
        readSources.deallocate()
        writeSources.deallocate()
    }
}
