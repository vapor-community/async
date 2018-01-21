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
    public func onInput(_ next: Transcriber.Input) -> Future<Void> {
        do {
            return try transcriber.transcribe(next).flatMap(to: Void.self) { next in
                return self.downstream!.onInput(next)
            }
        } catch {
            downstream?.onError(error)
            return .done
        }
    }

    public func onError(_ error: Error) {
        downstream?.onError(error)
    }

    public func onClose() {
        downstream?.onClose()
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: InputStream, S.Input == Output {
        downstream = AnyInputStream(inputStream)
    }
}
