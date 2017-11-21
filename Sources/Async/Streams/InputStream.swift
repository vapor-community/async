/// A type that accepts a stream of `Input`
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#implementing-an-example-stream)
public protocol InputStream: BaseStream {
    /// The input type for this stream.
    /// For example: Request, ByteBuffer, Client
    associatedtype Input

    /// Input will be passed here as it is received.
    func onInput(_ input: Input)

    /// Errors will be passed here as it is received.
    func onError(_ error: Error)
}
