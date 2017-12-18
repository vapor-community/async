/// A `OutputStream` is a provider of a potentially unbounded number of sequenced elements,
/// publishing them according to the demand received from its Subscriber(s).
///
/// A `OutputStream` can serve multiple `InputStream` subscribed dynamically
/// at various points in time. It may also choose to only serve oneat a time.
///
/// When serving multiple `InputStream`s, the `OutputStream` can support
/// either unicast or multicast streaming.
public protocol OutputStream: class {
    /// The type of element signaled.
    associatedtype Output

    /// Request Publisher to start streaming data.
    ///
    /// This is a "factory method" and can be called multiple times, each time starting
    /// a new Subscription. Each `OutputRequest` will work for only a single `InputStream`.
    ///
    /// A Subscriber should only subscribe once to a single `OutputStream`.
    ///
    /// If the `OutputStream` rejects the subscription attempt or otherwise fails it will
    /// signal the error via `InputStream.onError`.
    ///
    /// - parameter subscriber: the `InputStream` that will consume signals from this `OutputStream`
    func output<S>(to inputStream: S) where S: InputStream, S.Input == Output
}

// MARK: Convenience

extension OutputStream {
    /// Drains the output stream into another input/output stream which can be chained.
    ///
    /// Also chains the errors and close events to the connected input/output stream
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-basics/#chaining-streams)
    public func stream<S>(to stream: S) -> S where S: InputStream, S.Input == Self.Output {
        output(to: stream)
        return stream
    }
}

/// MARK: Any

/// Type erased OutputStream. This allows an output stream to be stored
/// as a non generic type.
public final class AnyOutputStream<Wrapped>: OutputStream {
    /// See OutputStream.Output
    public typealias Output = Wrapped

    /// This closure connects input streams to this output stream.
    /// Instead of accepting a generic stream, it accepts an AnyInputStream.
    /// This allows us to store the closure as a non-generic property.
    private let onOutput: (AnyInputStream<Wrapped>) -> ()

    /// Creates a new AnyOutputStream from the supplied OutputStream.
    public init<S>(_ wrapped: S) where S: OutputStream, S.Output == Wrapped {
        onOutput = { inputStream in
            wrapped.output(to: inputStream)
        }
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Wrapped == S.Input {
        onOutput(AnyInputStream<Wrapped>(inputStream))
    }
}
