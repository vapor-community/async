/// An asymmetric stream that translates `Input` to 0, 1, or more `Output`.
public protocol TranslatingStream {
    /// See InputStream.Input
    associatedtype Input

    /// See OutputStream.Output
    associatedtype Output

    /// Convert the `Input` to `Output`.
    /// See `TranslatingStreamResult` for possible cases.
    func translate(input: Input) -> TranslatingStreamResult<Output>
}

/// MARK: Stream

extension TranslatingStream {
    /// Convert this `TranslatingStream` to a `Stream`.
    public func stream(on worker: Worker) -> TranslatingStreamWrapper<Self> {
        return .init(translator: self, on: worker)
    }
}

/// MARK: Result

/// The result of a call to `TranslatingStream.translate`.
/// Encapsulates all possible asymmetric stream states.
public enum TranslatingStreamResult<Output> {
    /// The input contains less than one output, i.e. a partial output.
    /// The next call to `.translate` _must_ give a new input for consumption.
    case insufficient
    /// The input contained exactly one output.
    /// The next call to `.translate` _must_ give a new input for consumption.
    case sufficient(Output)
    /// The input contained more than one output, i.e. extraneous data.
    /// The next call to `.translate` _must_ give the same input for consumption.
    case excess(Output)
}

/// MARK: Wrapper

public final class TranslatingStreamWrapper<Translator>: Stream, ConnectionContext
    where Translator: TranslatingStream
{
    /// See InputStream.Input
    public typealias Input = Translator.Input

    /// See OutputStream.Output
    public typealias Output = Translator.Output

    /// Reference to the connected upstream.
    /// An output stream that supplies this stream with input.
    private var upstream: ConnectionContext?

    /// Reference to the connected downstream.
    /// An input stream that accepts this stream's output.
    private var downstream: AnyInputStream<Output>?

    /// The currently available input.
    private var currentInput: Input?

    /// The outstanding downstream demand.
    private var downstreamDemand: UInt

    /// The source translator stream.
    private var translator: Translator

    /// The event loop to dispatch recursive calls.
    private var eventLoop: EventLoop

    /// The current recursion depth.
    private var recursionDepth: Int

    /// Create a new TranslatingStreamWrapper.
    /// This is purposefully internal.
    /// Use `.stream()` on a translating stream to create.
    internal init(translator: Translator, on worker: Worker) {
        self.translator = translator
        self.eventLoop = worker.eventLoop
        downstreamDemand = 0
        recursionDepth = 0
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            downstream?.close()
            downstream = nil
            upstream = nil
        case .connect(let upstream):
            self.upstream = upstream
        case .error(let error):
            downstream?.error(error)
        case .next(let next):
            recursionDepth = 0
            self.currentInput = next
            update()
        }
    }

    /// See ConnectionContext.connection
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .cancel:
            upstream?.cancel()
            upstream = nil
            downstream = nil
        case .request(let count):
            if recursionDepth >= 64 {
                /// if we have exceeded the max recursion depth,
                /// dispatch the next update asynchronously
                eventLoop.async {
                    self.downstreamDemand += count
                    self.recursionDepth = 0
                    self.update()
                }
            } else {
                downstreamDemand += count
                recursionDepth += 1
                update()
            }
        }
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: InputStream, Output == S.Input {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }

    /// Updates the stream's state.
    private func update() {
        guard downstreamDemand > 0 else {
            return
        }

        guard let input = self.currentInput else {
            upstream?.request()
            return
        }

        switch translator.translate(input: input) {
        case .insufficient:
            /// the translator was unable to provide an output
            /// after consuming the entirety of the supplied input
            self.currentInput = nil
        case .sufficient(let output):
            /// the input created exactly 1 output.
            self.currentInput = nil
            downstreamDemand -= 1
            downstream?.next(output)
        case .excess(let output):
            /// the input contains more than 1 output.
            downstreamDemand -= 1
            downstream?.next(output)
        }

        update()
    }
}
