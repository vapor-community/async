import Dispatch
import Foundation

public final class DispatchEventLoop: EventLoop {
    public typealias Source = DispatchEventSource
    private let queue: DispatchQueue

    public var label: String {
        return queue.label
    }

    public init(label: String) {
        queue = DispatchQueue(label: label)
    }

    public func onReadable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> DispatchEventSource {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { callback(false) }
        source.setCancelHandler { callback(true) }
        return .read(source)
    }

    public func onWritable(descriptor: Int32, _ callback: @escaping EventLoop.EventCallback) -> DispatchEventSource {
        let source = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { callback(false) }
        source.setCancelHandler { callback(true) }
        return .write(source)
    }

    public func run() {
        RunLoop.main.run()
    }
}

public enum DispatchEventSource: EventSource {
    case read(DispatchSourceRead)
    case write(DispatchSourceWrite)

    public func suspend() {
        switch self {
        case .read(let read): read.suspend()
        case .write(let write): write.suspend()
        }
    }

    public func resume() {
        switch self {
        case .read(let read): read.resume()
        case .write(let write): write.resume()
        }
    }

    public func cancel() {
        switch self {
        case .read(let read): read.cancel()
        case .write(let write): write.cancel()
        }
    }
}
