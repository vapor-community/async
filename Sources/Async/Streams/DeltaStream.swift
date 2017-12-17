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
public final class DeltaStream<Splitting>: TransformingStream {
    /// See InputStream.Input
    public typealias Input = Splitting

    /// See OutputStream.Output
    public typealias Output = Splitting

    /// Handles input
    public typealias OnInput = (Input) throws -> ()
    private let onInput: OnInput

    /// Current output request
    public var upstream: ConnectionContext?

    /// Connected stream
    public var downstream: AnyInputStream<Splitting>?

    /// Create a new delta stream.
    public init(
        _ splitting: Splitting.Type = Splitting.self,
        onInput: @escaping OnInput
    ) {
        self.onInput = onInput
    }

    /// See TransformingStream.transform
    public func transform(_ input: Splitting) throws -> Future<Splitting> {
        try onInput(input)
        return Future(input)
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

