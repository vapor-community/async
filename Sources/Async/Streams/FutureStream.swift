/// Converts some future returning method to a `TransformingStream`.
public final class FutureStream<In, Out>: TransformingStream {
    /// See InputStream.Input
    public typealias Input = In

    /// See InputStream.Output
    public typealias Output = Out

    /// See TransformingStream.upstream
    public var upstream: ConnectionContext?

    /// See TransformingStream.downstream
    public var downstream: AnyInputStream<FutureStream.Output>?

    /// Accepts input and returns a future output
    public typealias OnTransform = (Input) throws -> (Future<Output>)

    /// Stores the transforming closure
    private let onTransform: OnTransform

    /// Create a new future stream.
    public init(onTransform: @escaping OnTransform) {
        self.onTransform = onTransform
    }

    /// See TransformingStream.transform
    public func transform(_ input: Input) throws -> Future<Output> {
        return try onTransform(input)
    }
}
