/// `TransformingStream`s yield exactly one output for every input.
///
/// The output yielded may be a `Future`. If the transformed `Future`
/// results in an error, it will be forwarded downstream.
///
/// All other input events not affected by the transform are simply
/// forwarded downstream.
///
/// The transforming stream's downstream will be automatically connected to
/// its upstream, allowing backpressure to pass through unhindered.
public protocol TransformingStream: Stream {
    /// `ConnectionContext` for the connected, upstream
    /// `OutputStream` that is supplying this stream with input.
    var upstream: ConnectionContext? { get set }

    /// Connected, downstream `InputStream` that is accepting
    /// this stream's output.
    var downstream: AnyInputStream<Output>? { get set }

    /// Transforms the input to output
    func transform(_ input: Input) throws -> Future<Output>
}

extension TransformingStream {
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
                try downstream.flatMap(transform(input).stream)
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
