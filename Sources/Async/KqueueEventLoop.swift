import Darwin

public final class KqueueEventLoop: EventLoop {
    public typealias Source = KqueueEventSource

    private let kq: Int32
    private var eventlist: [kevent]
    internal var changelist: [kevent]

    public init() throws {
        let status = kqueue()
        if status == -1 {
            throw EventLoopError(identifier: "kqueue", reason: "Could not create kqueue.")
        }
        self.kq = status
        eventlist = []
        changelist = []
    }

    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> KqueueEventSource {
        let source = KqueueEventSource(callback: callback, queue: self)
        var event = kevent()
        event.ident = UInt(descriptor)
        event.filter = Int16(EVFILT_READ)
        event.flags = UInt16(EV_ADD | EV_DISABLE)
        event.fflags = 0
        event.data = 0
        event.udata = source.makePointer()
        changelist.append(event)
        eventlist.append(.init())
        return source
    }

    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> KqueueEventSource {
        let source = KqueueEventSource(callback: callback, queue: self)
        var event = kevent()
        event.ident = UInt(descriptor)
        event.filter = Int16(EVFILT_WRITE)
        event.flags = UInt16(EV_ADD | EV_DISABLE)
        event.fflags = 0
        event.data = 0
        event.udata = source.makePointer()
        changelist.append(event)
        eventlist.append(.init())
        return source
    }

    public func run() {
        while true {
            let eventCount = kevent(kq, &changelist, Int32(changelist.count), &eventlist, Int32(eventlist.count), nil)
            guard eventCount >= 0 else {
                print("An error occured while running kevent: \(eventCount).")
                continue
            }

            for i in 0..<Int(eventCount) {
                let event = eventlist[i]
                if event.flags & UInt16(EV_ERROR) > 0 {
                    let reason = String(cString: strerror(Int32(event.data)))
                    print("An error occured during an event: \(reason)")
                    continue
                }

                for change in changelist {
                    if event.ident == change.ident && event.filter == change.filter {
                        let source = KqueueEventSource.makeSource(from: event.udata)
                        source.signal()
                    }
                }
            }
        }
    }
}

public final class KqueueEventSource: EventSource {
    private let callback: EventLoop.EventCallback
    private var pointer: UnsafeMutablePointer<KqueueEventSource>?
    private var active: Bool
    private let queue: KqueueEventLoop
    private let changeindex: Int

    internal init(callback: @escaping EventLoop.EventCallback, queue: KqueueEventLoop) {
        self.callback = callback
        active = false
        self.queue = queue
        changeindex = queue.changelist.count
    }

    public func suspend() {
        guard active else {
            fatalError("Called `.suspend()` on a suspended KqueueEventSource.")
        }
        queue.changelist[changeindex].flags = UInt16(EV_ADD | EV_DISABLE)
        active = false
    }

    public func resume() {
        guard !active else {
            fatalError("Called `.resume()` on a resumed KqueueEventSource.")
        }
        queue.changelist[changeindex].flags = UInt16(EV_ADD | EV_ENABLE)
        active = true
    }

    internal func signal() {
        if active {
            callback(false)
        }
    }

    func makePointer() -> UnsafeMutableRawPointer {
        let pointer = UnsafeMutablePointer<KqueueEventSource>.allocate(capacity: 1)
        pointer.pointee = self
        self.pointer = pointer
        return UnsafeMutableRawPointer(pointer)
    }

    static func makeSource(from pointer: UnsafeMutableRawPointer) -> KqueueEventSource {
        let pointer = pointer.assumingMemoryBound(to: KqueueEventSource.self)
        return pointer.pointee
    }


    deinit {
        queue.changelist[changeindex].flags = UInt16(EV_DELETE)
        pointer?.deallocate(capacity: 1)
        pointer?.deinitialize()
    }
}
