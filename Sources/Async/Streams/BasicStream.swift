/// A basic, generic stream implementation.
public final class BasicStream<Data>: Stream, ClosableStream {
    /// See InputStream.Input
    public typealias Input = Data

    /// See OutputStream.Output
    public typealias Output = Data

    /// A closure that takes an input.
    public typealias OnInput = (Input) throws -> ()

    /// Pass output as it is generated to this stream.
    public var inputClosure: OnInput

    /// A closure that takes an error.
    public typealias OnError = (Error) -> ()

    /// Pass output as it is generated to this stream.
    public var errorClosure: OnError

    /// A closure for handling on close events
    public typealias OnClose = () -> ()

    /// See CloseableStream.close
    public var closeClosure: OnClose

    /// See InputStream.onInput
    public func onInput(_ input: Data) {
        do {
            try self.inputClosure(input)
        } catch {
            self.onError(error)
        }
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        errorClosure(error)
    }

    /// See OutputStream.onOutput
    public func onOutput<I>(_ input: I) where I: InputStream, Data == I.Input {
        inputClosure = input.onInput
        errorClosure = input.onError
    }

    /// See CloseableStream.onClose(_:)
    public func onClose(_ onClose: ClosableStream) {
        closeClosure = onClose.close
    }

    /// See CloseableStream.close
    public func close() {
        closeClosure()
    }

    /// Create a new BasicStream generic on the supplied type.
    public init(
        _ data: Data.Type = Data.self,
        onInput: @escaping OnInput = { _ in },
        onError: @escaping OnError = { _ in },
        onClose: @escaping OnClose = { }
    ) {
        self.inputClosure = onInput
        self.errorClosure = onError
        self.closeClosure = onClose
    }

    @discardableResult
    /// Sets this stream's error clsoure
    public func `catch`(onError: @escaping OnError) -> Self {
        self.errorClosure = onError
        return self
    }
}
