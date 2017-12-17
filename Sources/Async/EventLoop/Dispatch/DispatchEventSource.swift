import Dispatch

/// Dispatch based `EventSource` implementation.
public final class DispatchEventSource: EventSource {
    /// See EventSouce.state
    public var state: EventSourceState

    /// The underlying dispatch source.
    private var source: DispatchSourceProtocol

    /// Create a new
    internal init(source: DispatchSourceProtocol) {
        self.source = source
        state = .suspended
    }

    /// See EventSource.suspend
    public func suspend() {
        source.suspend()
        state = .suspended
    }

    /// See EventSource.resume
    public func resume() {
        source.suspend()
        state = .resumed
    }

    /// See EventSource.cancel
    public func cancel() {
        source.cancel()
        state = .cancelled
    }
}
