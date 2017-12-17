import Darwin

public final class KqueueEventLoop: EventLoop {
    public typealias Source = KqueueEventSource

    private let kq: Int32
    internal var eventlist: [kevent]
    internal var sources: [KqueueEventSource]

    public init() throws {
        let status = kqueue()
        if status == -1 {
            throw EventLoopError(identifier: "kqueue", reason: "Could not create kqueue.")
        }
        self.kq = status
        eventlist = []
        sources = []

        for _ in 0..<32 {
            /// 32 max
            eventlist.append(kevent())
        }
    }

    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> KqueueEventSource {
        let source = KqueueEventSource(descriptor: descriptor, kq: kq, callback: callback)
        source.event.filter = Int16(EVFILT_READ)
        sources.append(source)
        return source
    }

    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> KqueueEventSource {
        let source = KqueueEventSource(descriptor: descriptor, kq: kq, callback: callback)
        source.event.filter = Int16(EVFILT_WRITE)
        sources.append(source)
        return source
    }

    public func run() {
        while true {
            let eventCount = kevent(kq, nil, 0, &eventlist, Int32(eventlist.count), nil)
            guard eventCount >= 0 else {
                print("An error occured while running kevent: \(eventCount).")
                continue
            }
            for i in 0..<Int(eventCount) {
                let event = eventlist[i]
                for source in sources {
                    if event.ident == source.event.ident && event.filter == source.event.filter {
                        if event.flags & UInt16(EV_ERROR) > 0 {
                            let reason = String(cString: strerror(Int32(event.data)))
                            print("An error occured during an event: \(reason)")
                            continue
                        }

                        if event.flags & UInt16(EV_EOF) > 0 {
                            source.signal(true)
                        } else {
                            source.signal(false)
                        }
                    }
                }
            }
        }
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
        update()
    }

    private func update() {
        guard !isCancelled else {
            return
        }

        let response = kevent(kq, &event, 1, nil, 0, nil)
        if response < 0 {
            // print("An error occured during update: \(response)")
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
        event.flags = UInt16(EV_DELETE)
        update()
        isCancelled = true
    }

    internal func signal(_ eof: Bool) {
        guard isActive && !isCancelled else {
            return
        }

        callback(eof)
    }
}
