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

/// Config options for an event source.
public struct EventSourceConfig {
    /// The trigger type for this event source.
    public let trigger: EventSourceTrigger

    /// Creates a new `EventSourceConfig`
    public init(trigger: EventSourceTrigger) {
        self.trigger = trigger
    }
}

/// Supported event source trigger modes.
public enum EventSourceTrigger {
    /// The event will be triggered whenever
    /// the state _changes_ to the desired state.
    /// The state should be considered no longer desirable
    /// when calls to the system return "would block" indiciations.
    case edge
    /// The event will be triggered every time
    /// the state is == to the desired state.
    case level
}
