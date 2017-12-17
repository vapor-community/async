import Darwin
import Foundation

public final class KqueueEventLoop: EventLoop {
    public typealias Source = KqueueEventSource

    public let label: String

    private let kq: Int32
    private var eventlist: UnsafeMutableBufferPointer<kevent>
    private var readSources: UnsafeMutableBufferPointer<KqueueEventSource>
    private var writeSources: UnsafeMutableBufferPointer<KqueueEventSource>

    public init(label: String) throws {
        self.label = label
        let status = kqueue()
        if status == -1 {
            throw EventLoopError(identifier: "kqueue", reason: "Could not create kqueue.")
        }
        self.kq = status
        eventlist = .allocate(count: 4096)
        readSources = .allocate(count: 4096)
        writeSources = .allocate(count: 4096)
    }

    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> KqueueEventSource {
        let source = KqueueEventSource(descriptor: descriptor, kq: kq, callback: callback)
        source.event.filter = Int16(EVFILT_READ)
        readSources[Int(descriptor)] = source
        return source
    }

    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> KqueueEventSource {
        let source = KqueueEventSource(descriptor: descriptor, kq: kq, callback: callback)
        source.event.filter = Int16(EVFILT_WRITE)
        writeSources[Int(descriptor)] = source
        return source
    }

    public func run() {
        print("[\(label)] Running")
        run: while true {
            let eventCount = kevent(kq, nil, 0, eventlist.baseAddress, Int32(eventlist.count), nil)
            guard eventCount >= 0 else {
                print("An error occured while running kevent: \(eventCount).")
                continue
            }
            /// print("[\(label)] \(eventCount) New Events")
            e: for i in 0..<Int(eventCount) {
                let event = eventlist[i]

                let source: KqueueEventSource
                switch Int32(event.filter) {
                case EVFILT_READ:
                    source = readSources[Int(event.ident)]
                case EVFILT_WRITE:
                    source = writeSources[Int(event.ident)]
                default: fatalError()
                }

                if event.flags & UInt16(EV_ERROR) > 0 {
                    let reason = String(cString: strerror(Int32(event.data)))
                    print("An error occured during an event: \(reason)")
                } else if event.flags & UInt16(EV_EOF) > 0 {
                    source.signal(true)
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

extension UnsafeMutableBufferPointer {
    fileprivate static func allocate(count: Int) -> UnsafeMutableBufferPointer<Element> {
        let pointer = UnsafeMutablePointer<Element>.allocate(capacity: count)
        return .init(start: pointer, count: count)
    }

    fileprivate func deallocate() {
        baseAddress?.deinitialize()
        baseAddress?.deallocate(capacity: count)
    }
}

public final class KqueueEventSource: EventSource {
    private let callback: EventLoop.EventCallback
    private var isActive: Bool
    private var isCancelled: Bool
    var event: kevent
    let kq: Int32

    internal init(descriptor: Int32, kq: Int32, callback: @escaping EventLoop.EventCallback) {
        self.callback = callback
        isActive = false
        isCancelled = false
        self.kq = kq
        var event = kevent()
        event.ident = UInt(descriptor)
        event.flags = UInt16(EV_ADD | EV_DISABLE)
        event.fflags = 0
        event.data = 0
        self.event = event
    }

    private func update() {
        guard !isCancelled else {
            return
        }

        let response = kevent(kq, &event, 1, nil, 0, nil)
        if response < 0 {
            let reason = String(cString: strerror(errno))
            print("An error occured during KqueueEventSource.update: \(reason)")
        }
    }

    public func suspend() {
        guard isActive else {
            fatalError("Called `.suspend()` on a suspended KqueueEventSource.")
        }
        guard !isCancelled else {
            fatalError("Called `.suspend()` on a cancelled KqueueEventSource.")
        }

        event.flags = UInt16(EV_ADD | EV_DISABLE)
        update()
        isActive = false
    }

    public func resume() {
        guard !isActive else {
            fatalError("Called `.resume()` on a resumed KqueueEventSource.")
        }
        guard !isCancelled else {
            fatalError("Called `.resume()` on a cancelled KqueueEventSource.")
        }

        event.flags = UInt16(EV_ADD | EV_ENABLE)
        update()
        isActive = true
    }

    public func cancel() {
        guard !isCancelled else {
            fatalError("Called `.cancel()` on a cancelled KqueueEventSource.")
        }
        event.flags = UInt16(EV_DELETE)
        isCancelled = true
    }

    internal func signal(_ eof: Bool) {
        guard isActive && !isCancelled else {
            return
        }

        if eof {
            isCancelled = true
        }
        callback(eof)
    }
}
