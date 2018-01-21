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

public final class TranslatingStreamWrapper<Translator>: Stream
    where Translator: TranslatingStream
{
    /// See InputStream.Input
    public typealias Input = Translator.Input

    /// See OutputStream.Output
    public typealias Output = Translator.Output

    /// Reference to the connected downstream.
    /// An input stream that accepts this stream's output.
    private var downstream: AnyInputStream<Output>?

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
        upstreamIsClosed = false
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            var input = TranslatingStreamInput<Input>(condition: .close)
            upstreamIsClosed = true
            let promise = Promise(Void.self) // ignore result, since stream is closed
            update(input: &input, ready: promise)
        case .error(let error):
            downstream?.error(error)
        case .next(let next, let ready):
            var input = TranslatingStreamInput<Input>(condition: .next(next))
            update(input: &input, ready: ready)
        }
    }

    /// Closes downstream and clears references.
    private func close() {
        downstream?.close()
        downstream = nil
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: InputStream, Output == S.Input {
        downstream = AnyInputStream(inputStream)
    }

    /// Updates the stream's state.
    private func update(input: inout TranslatingStreamInput<Input>, ready: Promise<Void>) {
        var output: TranslatingStreamOutput<Output>
        do {
            output = try translator.translate(input: &input)
        } catch {
            self.error(error)
            ready.complete()
            return
        }

        var shouldClose = input.shouldClose
        var input = input
        output.result.do { state in
            switch state {
            case .insufficient:
                /// the translator was unable to provide an output
                /// after consuming the entirety of the supplied input
                if self.upstreamIsClosed {
                    shouldClose = true
                }
                ready.complete()
            case .sufficient(let output):
                /// the input created exactly 1 output.
                self.downstream?.next(output, ready)
            case .excess(let output):
                /// the input contains more than 1 output.
                self.downstream?.next(output).do {
                    self.update(input: &input, ready: ready)
                }.catch { error in
                    ready.fail(error)
                }
            }
            if shouldClose {
                self.close()
            }
        }.catch { error in
            self.downstream?.error(error)
            if shouldClose { self.close() }
            ready.complete()
        }
    }
}
