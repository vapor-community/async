/// `TranscribingStream`s yield exactly one output for every input.
///
/// The output yielded may be a `Future`. If the transformed `Future`
/// results in an error, it will be forwarded downstream.
///
/// All other input events not affected by the transform are simply
/// forwarded downstream.
///
/// The transforming stream's downstream will be automatically connected to
/// its upstream, allowing backpressure to pass through unhindered.
public protocol TranscribingStream {
    /// See InputStream.Input
    associatedtype Input

    /// See OutputStream.Output
    associatedtype Output

    /// Transforms the input to output
    func transcribe(_ input: Input) throws -> Future<Output>
}

extension TranscribingStream {
    /// Convert this `TranscribingStream` to a `Stream`.
    public func stream() -> TranscribingStreamWrapper<Self> {
        return .init(transcriber: self)
    }
}


public final class TranscribingStreamWrapper<Transcriber>: Stream where Transcriber: TranscribingStream {
    /// See InputStream.Input
    public typealias Input = Transcriber.Input

    /// See OutputStream.Output
    public typealias Output = Transcriber.Output

    /// `ConnectionContext` for the connected, upstream
    /// `OutputStream` that is supplying this stream with input.
    public var upstream: ConnectionContext?

    /// Connected, downstream `InputStream` that is accepting
    /// this stream's output.
    public var downstream: AnyInputStream<Output>?

    /// The internal transcriber
    private let transcriber: Transcriber

    /// Create a new `TranscribingStreamWrapper`.
    /// This is purposefully internal.
    /// Use `.stream()` on a `TranscribingStream` to create.
    internal init(transcriber: Transcriber) {
        self.transcriber = transcriber
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            downstream?.close()
        case .connect(let upstream):
            self.upstream = upstream
            downstream?.connect(to: upstream)
        case .error(let error):
            downstream?.error(error)
        case .next(let input):
            do {
                try downstream.flatMap(transcriber.transcribe(input).stream)
            } catch {
                downstream?.error(error)
            }
        }
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: InputStream, S.Input == Output {
        downstream = AnyInputStream(inputStream)
        upstream.flatMap(inputStream.connect)
    }
}
