import Foundation
import Darwin

// TODO: Do we need to stop the thread?
// TODO: Do we expose an initializer?
// TODO: Make use of Foundation.Thread internally (pthread wrapper)?
// TODO: Can a thread be paused?
// TODO: Do we provide type-safe input/output for communicating with the thread?
// TODO: Do we abstract this thread? Or do we focus on our own specific use case?
// TODO:   If abstracting; do we make a simple DispatchSource-like wrapper by default?
// TODO: Can this be a (pre-)configurable set of tasks?
// TODO: Do we provide thread contexts like Foundation.Thread?

fileprivate let key = DispatchSpecificKey<EventLoop>()

public final class EventLoop {
    typealias Callback = (() -> ())
    
    final class RequestHandle {
        fileprivate typealias Toggle = (Bool) -> ()
        fileprivate typealias Remove = (Int32) -> ()
        
        fileprivate var descriptor: Int32
        fileprivate var callback: Toggle
        fileprivate var remove: Remove
        
        fileprivate init(descriptor: Int32, remove: @escaping Remove, _ callback: @escaping Toggle) {
            self.descriptor = descriptor
            self.callback = callback
            self.remove = remove
        }
        
        func resume() {
            callback(true)
        }
        
        func stop() {
            callback(false)
        }
        
        deinit {
            remove(self.descriptor)
        }
    }
    
    struct ReadRequest {
        var descriptor: Int32
        var callback: (() -> ())
        var active: Bool
    }
    
    struct WriteRequest {
        var descriptor: Int32
        var callback: (() -> ())
        var active: Bool
    }
    
    fileprivate var thread: Thread!
    var running = true
    var timeout: timeval
    
    var largestFD: Int32 = 0
    var read = fd_set()
    var write = fd_set()
    
    fileprivate var reading = [ReadRequest]()
    fileprivate var writing = [WriteRequest]()
    
    func updateWriteFDs() {
        var active = writing.flatMap { request in
            return request.active ? request.descriptor : 0
        }
    }
    
    func updateReadFDs() {
        var active = writing.flatMap { request in
            return request.active ? request.descriptor : 0
        }
    }
    
    func onReadable(descriptor: Int32, _ callback: @escaping Callback) -> RequestHandle {
        if descriptor > largestFD {
            largestFD = descriptor
        }
        
        let request = ReadRequest(descriptor: descriptor, callback: callback, active: true)
        self.reading.append(request)
        
        return RequestHandle(descriptor: descriptor, remove: removeReadCallback) { state in
            for i in 0..<self.reading.count {
                self.reading[i].active = state
            }
        }
    }
    
    func removeReadCallback(descriptor: Int32) {
        if let index = self.reading.index(where: { $0.descriptor == descriptor }) {
            self.reading.remove(at: index)
        }
    }
    
    func removeWriteCallback(descriptor: Int32) {
        if let index = self.writing.index(where: { $0.descriptor == descriptor }) {
            self.writing.remove(at: index)
        }
    }
    
    func onWritable(descriptor: Int32, _ callback: @escaping Callback) -> RequestHandle {
        if descriptor > largestFD {
            largestFD = descriptor
        }
        
        let request = WriteRequest(descriptor: descriptor, callback: callback, active: true)
        self.writing.append(request)
        
        return RequestHandle(descriptor: descriptor, remove: removeWriteCallback) { state in
            for i in 0..<self.reading.count {
                self.reading[i].active = state
            }
        }
    }
    
    public static var current: EventLoop? {
        return Thread.current.threadDictionary["async:eventloop"] as? EventLoop
    }
    
    init() {
        self.timeout = timeval()
        self.timeout.tv_sec = 1
        
        if #available(OSX 10.12, *) {
            self.thread = Thread(block: run)
        } else {
            fatalError("Unsupported platform")
        }
    }
    
    func run() {
        Thread.current.threadDictionary["async:eventloop"] = self
        
        while running {
            let result = select(self.largestFD + 1, &read, &write, nil, &timeout)
            kqueue
        }
    }
    
    public static func makePool<Params>(
        count: Int,
        input: Params,
        _ main: @escaping (Params) -> Void
    ) -> [EventLoop] {
        var pool = [EventLoop]()
        
        for _ in 0..<count {
            pool.append(EventLoop())
        }
        
        return pool
    }
 }

/// An error converting types.
public struct EventLoopError: Error {
    /// See Debuggable.reason
    var reason: String
    
    /// See Debuggable.identifier
    var identifier: String
    
    /// Creates a new core error.
    init(identifier: String, reason: String) {
        self.reason = reason
        self.identifier = identifier
    }
}
