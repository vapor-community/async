/// A stream is both an InputStream and an OutputStream
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#implementing-an-example-stream)
public typealias Stream = InputStream & OutputStream

/// Base stream protocol. Simply handles errors.
/// All streams are expected to reset themselves
/// after reporting an error and be ready for
/// additional incoming data.
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#implementing-an-example-stream)
public protocol BaseStream: class {
    /// Closures that can handle this stream's output.
    typealias ErrorHandler = ErrorClosure

    /// Pass any errors that are thrown to
    /// the error stream
    var errorStream: ErrorClosure { get set }
}

/// Reference type for error closures.
public final class ErrorClosure {
    /// A closure that takes an error.
    public typealias Closure = (Error) -> ()

    /// Pass error as it is generated to this stream.
    public var closure: Closure

    /// Creates a new error closure.
    public init(_ closure: @escaping Closure = { _ in }) {
        self.closure = closure
    }
}

extension BaseStream {
    /// Drains the output stream into a closure
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#catching-stream-errors)
    @discardableResult
    public func `catch`(_ handler: @escaping ErrorHandler.Closure) -> Self {
        self.errorStream.closure = handler
        return self
    }

    /// Reports an error to the stream.
    public func report(_ error: Error) {
        self.errorStream.closure(error)
    }
}
