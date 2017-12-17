public protocol EventLoop {
    associatedtype Source: EventSource
    typealias EventCallback = (Bool) -> ()

    var label: String { get }
    init(label: String) throws

    func onReadable(descriptor: Int32, _ callback: @escaping EventCallback) -> Source
    func onWritable(descriptor: Int32, _ callback: @escaping EventCallback) -> Source
    func run()
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
