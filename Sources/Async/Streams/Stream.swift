/// A `Stream` represents a processing stage—which is both a `InputStream`
/// and a `OutputStream` and obeys the contracts of both.
public typealias Stream = InputStream & OutputStream

/// A type-erased stream. This allows for a stream
/// to be stored or passed as a non-generic type.
public final class AnyStream<WrappedInput, WrappedOutput>: Stream {
    /// See InputStream.Input
    public typealias Input = WrappedInput

    /// See OutputStream.Output
    public typealias Output = WrappedOutput

    /// Combine type erased input and output streams to
    /// create the combined stream.
    private let inputStream: AnyInputStream<WrappedInput>
    private let outputStream: AnyOutputStream<WrappedOutput>

    /// Create a new type-erased stream.
    public init<S>(_ wrapped: S) where S: Stream, S.Input == Input, S.Output == Output {
        inputStream = .init(wrapped)
        outputStream = .init(wrapped)
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<WrappedInput>) {
        inputStream.input(event)
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, WrappedOutput == S.Input {
        outputStream.output(to: inputStream)
    }
}
