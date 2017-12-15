/// Copies output from an output stream into an array
/// of stream split deltas.
///
/// Example using a splitter to split a stream of numbers:
///
///     let numberEmitter = EmitterStream<Int>()
///
///     var output: [Int] = []
///
///     numberEmitter.split { int, req in
///         output.append(int)
///         req.requestOutput()
///     }.split { int, req in
///         output.append(int)
///         req.requestOutput()
///     }
///
///     numberEmitter.emit(1)
///     numberEmitter.emit(2)
///     numberEmitter.emit(3)
///
///     print(output) /// [1, 1, 2, 2, 3, 3]
///
public final class DeltaStream<Splitting>: Stream, ConnectionContext {
    /// See InputStream.Input
    public typealias Input = Splitting

    /// See OutputStream.Output
    public typealias Output = Splitting

    /// Handles input
    public typealias OnInput = (Input) throws -> ()
    private let onInput: OnInput

    /// Current output request
    private var upstream: ConnectionContext?

    /// Connected stream
    private var downstream: AnyInputStream<Splitting>?

    /// Create a new delta stream.
    public init(
        _ splitting: Splitting.Type = Splitting.self,
        onInput: @escaping OnInput
    ) {
        self.onInput = onInput
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<Splitting>) {
        switch event {
        case .next(let input): do { try onInput(input) } catch { downstream?.error(error) }
        default: downstream?.input(event)
        }
    }

    /// See ConnectionContext.connection
    public func connection(_ event: ConnectionEvent) {
        upstream?.connection(event)
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Splitting == S.Input {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }
}

extension OutputStream {
    /// Splits the stream output into the supplied closure.
    /// This will not consume output like `.drain`. Output will
    /// continue flowing through the stream unaffected.
    /// note: Errors thrown in this closure will exit through the error stream.
    public func split(
        onInput: @escaping DeltaStream<Output>.OnInput
    ) -> DeltaStream<Output> {
        let delta = DeltaStream(Output.self, onInput: onInput)
        return stream(to: delta)
    }
}

