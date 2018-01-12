/// An event source created by an event loop.
public protocol EventSource: class {
    /// This source's current state
    var state: EventSourceState { get }

    /// Suspends the source.
    func suspend()

    /// Resumes the source.
    func resume()

    /// Cancels the source.
    func cancel()
}

/// Supported source states
public enum EventSourceState {
    /// The source's handler will be called when
    /// there is new data.
    case resumed
    
    /// New data is being buffered or dropped by the system.
    /// Your handler will not be called until resumed.
    case suspended

    /// Any new data will be dropped. Your handler will not be
    /// called. Cannot be resumed or suspended.
    case cancelled
}
