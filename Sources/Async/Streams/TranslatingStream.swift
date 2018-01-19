/// An asymmetric stream that translates `Input` to 0, 1, or more `Output`.
public protocol TranslatingStream {
    /// See InputStream.Input
    associatedtype Input

    /// See OutputStream.Output
    associatedtype Output

    /// Convert the `Input` to `Output`.
    /// See `TranslatingStreamResult` for possible cases.
    func translate(input: inout TranslatingStreamInput<Input>) throws -> TranslatingStreamOutput<Output>
}

/// MARK: Stream

extension TranslatingStream {
    /// Convert this `TranslatingStream` to a `Stream`.
    public func stream(on worker: Worker) -> TranslatingStreamWrapper<Self> {
        return .init(translator: self, on: worker)
    }
}

/// MARK: Input

/// The context supplied to `TranslatingStream.translate`.
public struct TranslatingStreamInput<Input> {
    /// Accesses the current input. If `nil`, the input stream has closed.
    public var input: Input? {
        switch condition {
        case .close: return nil
        case .next(let i): return i
        }
    }

    /// Shoudl close storage
    internal var shouldClose: Bool

    /// The internal condition storage.
    internal var condition: TranslatingStreamCondition<Input>

    /// Create a new `TranslatingStreamInput` internally.
    init(condition: TranslatingStreamCondition<Input>) {
        self.condition = condition
        self.shouldClose = false
    }

    /// Manually close downstream.
    public mutating func close() {
        self.shouldClose = true
    }
}

/// All possible translating stream input states.
internal enum TranslatingStreamCondition<Input> {
    case close
    case next(Input)
}


/// MARK: Output

/// The result of a call to `TranslatingStream.translate`.
/// Encapsulates all possible asymmetric stream states.
public struct TranslatingStreamOutput<Output> {
    /// Internal result type
    internal var result: Future<TranslatingStreamResult<Output>>

    /// The input contains less than one output, i.e. a partial output.
    /// The next call to `.translate` _must_ give a new input for consumption.
    public static func insufficient() -> TranslatingStreamOutput<Output> {
        return .init(result: Future(.insufficient))
    }

    /// The input contained exactly one output.
    /// The next call to `.translate` _must_ give a new input for consumption.
    public static func sufficient(_ output: Output) -> TranslatingStreamOutput<Output> {
        return .init(result: Future(.sufficient(output)))
    }

    /// The input contained more than one output, i.e. extraneous data.
    /// The next call to `.translate` _must_ give the same input for consumption.
    public static func excess(_ output: Output) -> TranslatingStreamOutput<Output> {
        return .init(result: Future(.excess(output)))
    }

    /// Maps a Future to a non-future `TranslatingStreamOutput<Output>` return.
    public static func map<T>(_ future: Future<T>, callback: @escaping (T) -> TranslatingStreamOutput<Output>) -> TranslatingStreamOutput<Output> {
        let future = future.map(to: TranslatingStreamOutput<Output>.self, callback).flatMap(to: TranslatingStreamResult<Output>.self) { output in
            return output.result
        }
        return TranslatingStreamOutput<Output>(result: future)
    }
}

/// Encapsulates all possible asymmetric stream states.
internal enum TranslatingStreamResult<Output> {
    case insufficient
    case sufficient(Output)
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

    /// True if closed
    private var upstreamIsClosed: Bool

    /// Create a new `TranslatingStreamWrapper`.
    /// This is purposefully internal.
    /// Use `.stream()` on a translating stream to create.
    internal init(translator: Translator, on worker: Worker) {
        self.translator = translator
        self.eventLoop = worker.eventLoop
        downstreamDemand = 0
        upstreamIsClosed = false
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            var input = TranslatingStreamInput<Input>(condition: .close)
            upstreamIsClosed = true
            update(input: &input)
        case .connect(let upstream):
            self.upstream = upstream
        case .error(let error):
            downstream?.error(error)
        case .next(let next):
            self.currentInput = next
            updateCheckingDemand()
        }
    }

    /// Closes downstream and clears references.
    private func close() {
        downstream?.close()
        downstream = nil
        upstream = nil
    }

    /// See ConnectionContext.connection
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .cancel:
            upstream?.cancel()
            upstream = nil
            downstream = nil
        case .request(let count):
            downstreamDemand += count
            updateCheckingDemand()
        }
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: InputStream, Output == S.Input {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }

    /// Updates the stream's state.
    private func updateCheckingDemand() {
        guard downstreamDemand > 0 else {
            return
        }

        guard let next = self.currentInput else {
            upstream?.request()
            return
        }

        var input = TranslatingStreamInput(condition: .next(next))
        self.update(input: &input)
    }

    /// Updates the stream's state.
    private func update(input: inout TranslatingStreamInput<Input>) {
        var output: TranslatingStreamOutput<Output>
        do {
            output = try translator.translate(input: &input)
        } catch {
            self.error(error)
            return
        }

        var shouldClose = input.shouldClose
        output.result.do { state in
            switch state {
            case .insufficient:
                /// the translator was unable to provide an output
                /// after consuming the entirety of the supplied input
                self.currentInput = nil
                if self.upstreamIsClosed {
                    shouldClose = true
                }
            case .sufficient(let output):
                /// the input created exactly 1 output.
                self.currentInput = nil
                self.downstreamDemand -= 1
                self.downstream?.next(output)
            case .excess(let output):
                /// the input contains more than 1 output.
                self.downstreamDemand -= 1
                self.downstream?.next(output)
            }
            if shouldClose {
                self.close()
            } else {
                self.updateCheckingDemand()
            }
        }.catch { error in
            self.downstream?.error(error)
            if shouldClose { self.close() }
        }
    }
}
