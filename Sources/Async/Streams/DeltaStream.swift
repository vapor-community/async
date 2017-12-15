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
public final class DeltaStream<Splitting>: Stream, OutputRequest {
    /// See InputStream.Input
    public typealias Input = Splitting

    /// See OutputStream.Output
    public typealias Output = Splitting

    /// Handles input
    public typealias OnInput = (Input) throws -> ()

    /// See OnInput
    private let onInputClosure: OnInput

    /// Current output request
    private var upstream: OutputRequest?

    /// Connected stream
    private var downstream: AnyInputStream?

    /// Create a new delta stream.
    public init(
        _ splitting: Splitting.Type = Splitting.self,
        onInput: @escaping OnInput
    ) {
        self.onInputClosure = onInput
    }

    public func requestOutput(_ count: UInt) {
        upstream?.requestOutput(count)
    }

    public func cancelOutput() {
        upstream?.cancelOutput()
    }

    /// See InputStream.onOutput
    public func onOutput(_ outputRequest: OutputRequest) {
        upstream = outputRequest
    }

    /// See InputStream.onInput
    public func onInput(_ input: Splitting) {
        do {
            try onInputClosure(input)
        } catch {
            onError(error)
        }
        downstream?.unsafeOnInput(input)
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        downstream?.onError(error)
    }

    /// See InputStream.onClose
    public func onClose() {
        downstream?.onClose()
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Splitting == S.Input {
        downstream = inputStream
        inputStream.onOutput(self)
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

