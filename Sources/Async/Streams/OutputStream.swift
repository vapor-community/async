/// A type that emits `Ouptut` asynchronously and at unspecified moments
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#implementing-an-example-stream)
public protocol OutputStream: BaseStream {
    /// The output type for this stream.
    /// For example: Request, ByteBuffer, Client
    associatedtype Output

    /// Closures that can handle this stream's output.
    typealias OutputHandler = OutputClosure<Output>

    /// Pass output as it is generated to this stream.
    var outputStream: OutputHandler { get set }
}

public final class OutputClosure<Output> {
    /// A closure that takes one onput.
    public typealias Closure = (Output) throws -> ()

    /// Pass output as it is generated to this stream.
    public var closure: Closure

    /// Creates a new output closure.
    public init(_ closure: @escaping Closure = { _ in }) {
        self.closure = closure
    }
}

extension OutputStream {
    /// Send output to stream, catching errors in
    /// the error stream.
    public func output(_ output: Output) {
        do {
            try outputStream.closure(output)
        } catch {
            errorStream.closure(error)
        }
    }
}

// MARK: Convenience

extension OutputStream {
    /// Drains the output stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func drain(_ handler: @escaping OutputHandler.Closure) -> Self {
        self.outputStream.closure = handler
        return self
    }


    /// Drains the output stream into another input/output stream which can be chained.
    ///
    /// Also chains the errors to the other input/output stream
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-basics/#chaining-streams)
    @discardableResult
    public func stream<S: Stream>(to stream: S) -> S where S.Input == Self.Output {
        stream.errorStream = self.errorStream
        self.outputStream.closure = stream.inputStream
        return stream
    }
}
