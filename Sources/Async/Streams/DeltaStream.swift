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
public final class DeltaStream<Splitting>: Stream {
    /// See InputStream.Input
    public typealias Input = Splitting

    /// See OutputStream.Output
    public typealias Output = Splitting

    /// Handles input
    public typealias OnInput = (Input, OutputRequest) throws -> ()

    /// See OnDrainingInput
    private let onInputClosure: OnInput

    /// Current output request
    private var outputRequest: OutputRequest?

    /// Initial output request size
    private let initialOutputRequest: UInt

    /// Connected stream
    private var connected: BasicStream<Splitting>

    /// Create a new delta stream.
    public init(
        _ splitting: Splitting.Type = Splitting.self,
        onInput: @escaping OnInput,
        initialOutputRequest: UInt
    ) {
        self.onInputClosure = onInput
        self.initialOutputRequest = initialOutputRequest
        connected = .init()
    }

    /// See InputStream.onOutput
    public func onOutput(_ outputRequest: OutputRequest) {
        self.outputRequest = outputRequest
        outputRequest.requestOutput(initialOutputRequest)
    }

    /// See InputStream.onInput
    public func onInput(_ input: Splitting) {
        if let outputRequest = self.outputRequest {
            do {
                try onInputClosure(input, outputRequest)
            } catch {
                onError(error)
            }
        }
        connected.onInput(input)
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        connected.onError(error)
    }

    /// See InputStream.onClose
    public func onClose() {
        connected.onClose()
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Splitting == S.Input {
        connected.output(to: inputStream)
    }
}

extension OutputStream {
    /// Splits the stream output into the supplied closure.
    /// This will not consume output like `.drain`. Output will
    /// continue flowing through the stream unaffected.
    /// note: Errors thrown in this closure will exit through the error stream.
    public func split(
        _ initialOutputRequest: UInt = 1,
        onInput: @escaping DeltaStream<Output>.OnInput
    ) -> DeltaStream<Output> {
        let delta = DeltaStream(Output.self, onInput: onInput, initialOutputRequest: initialOutputRequest)
        return stream(to: delta)
    }
}

