/// A `OutputStream` is a provider of a potentially unbounded number of sequenced elements,
/// publishing them according to the demand received from its Subscriber(s).
///
/// A `OutputStream` can serve multiple Subscribers subscribed dynamically
/// at various points in time.
public protocol OutputStream {
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
    /// Also chains the errors to the other input/output stream
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-basics/#chaining-streams)
    public func stream<S>(to stream: S) -> S where S: InputStream, S.Input == Self.Output {
        output(to: stream)
        return stream
    }

}
