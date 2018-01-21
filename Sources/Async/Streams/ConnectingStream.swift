///// A simple pass-through connecting stream.
///// This is useful for cases where you would like to convert
///// a function that accepts an `InputStream` to producing
///// an `OutputStream`.
//public final class ConnectingStream<Data>: Async.Stream {
//    /// See InputStream.Input
//    public typealias Input = Data
//
//    /// See OutputStream.Output
//    public typealias Output = Data
//
//    /// The connected upstream
//    private var upstream: ConnectionContext?
//
//    /// The connected downstream
//    private var downstream: AnyInputStream<Data>?
//
//    /// Create a new `ConnectingStream`
//    public init() {}
//
//    /// See InputStream.input
//    public func input(_ event: InputEvent<Data>) {
//        if let downstream = self.downstream {
//            downstream.input(event)
//        } else {
//            switch event {
//            case .connect(let upstream):
//                self.upstream = upstream
//            default: fatalError("No downstream connected")
//            }
//        }
//    }
//
//    /// See OutputStream.output
//    public func output<S>(to inputStream: S) where S : Async.InputStream, S.Input == Data {
//        downstream = AnyInputStream(inputStream)
//        upstream.flatMap(inputStream.connect)
//    }
//}

