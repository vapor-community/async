/// A type that emits `Ouptut` asynchronously and at unspecified moments
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#implementing-an-example-stream)
public protocol OutputStream: BaseStream {
    /// The output type for this stream.
    /// For example: Request, ByteBuffer, Client
    associatedtype Output

    /// Send output to the provided input stream.
    func onOutput<I: InputStream>(_ input: I) where I.Input == Output
}

// MARK: Convenience

extension OutputStream {
    /// Drains the output stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func drain(onInput: @escaping BasicStream<Output>.OnInput) -> BasicStream<Output> {
        let input = BasicStream<Output>(onInput: onInput)
        self.onOutput(input)
        return input
    }


    /// Drains the output stream into another input/output stream which can be chained.
    ///
    /// Also chains the errors to the other input/output stream
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-basics/#chaining-streams)
    @discardableResult
    public func stream<S: InputStream>(to stream: S) -> S where S.Input == Self.Output {
        self.onOutput(stream)
        return stream
    }
}
