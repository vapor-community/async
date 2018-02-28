/// A stream of byte buffers.
public protocol ByteStream: Stream
    where Self.Input == UnsafeBufferPointer<UInt8>, Self.Output == UnsafeBufferPointer<UInt8> { }

extension ByteStream {
    public typealias Input = UnsafeBufferPointer<UInt8>
    public typealias Output = UnsafeBufferPointer<UInt8>
}

/// A socket-based byte stream.
@available(*, deprecated)
public final class SocketStream<Socket>: ByteStream where Socket: Async.Socket {
    /// Socket source output stream.
    private let source: SocketSource<Socket>

    /// Socket sink input stream.
    private let sink: SocketSink<Socket>

    /// Use the static method on `Socket` to create.
    internal init(socket: Socket, on worker: Worker, onError: @escaping SocketSink<Socket>.ErrorHandler) {
        self.source = socket.source(on: worker)
        self.sink = socket.sink(on: worker, onError: onError)
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
    @available(*, deprecated)
    public func stream(on worker: Worker, onError: @escaping SocketSink<Self>.ErrorHandler) -> SocketStream<Self> {
        return .init(socket: self, on: worker, onError: onError)
    }
    
    /// Creates a `SocketStream` for this socket.
    @available(*, deprecated)
    public func stream(on worker: Worker) -> SocketStream<Self> {
        return .init(socket: self, on: worker) { _, error in
            ERROR("Uncaught error in SocketStream: \(error).")
        }
    }
}
