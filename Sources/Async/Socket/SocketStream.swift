/// A stream of byte buffers.
public protocol ByteStream: Stream
    where Input == UnsafeBufferPointer<UInt8>, Output == UnsafeBufferPointer<UInt8> { }

extension ByteStream {
    public typealias Input = UnsafeBufferPointer<UInt8>
    public typealias Output = UnsafeBufferPointer<UInt8>
}

/// A socket-based byte stream.
public final class SocketStream<Socket>: ByteStream where Socket: Async.Socket {
    /// Socket source output stream.
    private let source: SocketSource<Socket>

    /// Socket sink input stream.
    private let sink: SocketSink<Socket>

    /// Use the static method on `Socket` to create.
    internal init(socket: Socket, on worker: Worker) {
        self.source = socket.source(on: worker)
        self.sink = socket.sink(on: worker)
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<UnsafeBufferPointer<UInt8>>) {
        sink.input(event)
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, S.Input == UnsafeBufferPointer<UInt8> {
        source.output(to: inputStream)
    }
}

extension Socket {
    /// Creates a `SocketStream` for this socket.
    public func stream(on worker: Worker) -> SocketStream<Self> {
        return .init(socket: self, on: worker)
    }
}
