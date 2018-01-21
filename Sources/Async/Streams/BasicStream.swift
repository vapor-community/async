///// A basic, generic stream implementation.
//public final class ClosureStream<Data>: Stream {
//    /// See InputStream.Input
//    public typealias Input = Data
//
//    /// See OutputStream.Output
//    public typealias Output = Data
//
//    /// Handles output stream
//    public typealias OnOutput = (AnyInputStream<Data>) -> ()
//    private let onOutput: OnOutput
//
//    /// Handles input stream
//    public typealias OnInput = (Data) -> Future<Void>
//    private let onInput: OnInput
//
//    /// Handles connection context
//    public typealias OnConnection = (ConnectionEvent) -> ()
//    private let onConnection: OnConnection
//
//    /// Create a new BasicStream generic on the supplied type.
//    public init(
//        onInput: @escaping OnInput,
//        onOutput: @escaping OnOutput,
//        onConnection: @escaping OnConnection
//    ) {
//        self.onInput = onInput
//        self.onOutput = onOutput
//        self.onConnection = onConnection
//    }
//
//    /// See InputStream.input
//    public func input(_ event: InputEvent<Data>) {
//        onInput(event)
//    }
//
//    /// See OutputStream.output
//    public func output<S>(to inputStream: S) where S : InputStream, Data == S.Input {
//        let wrapped = AnyInputStream(inputStream)
//        onOutput(wrapped)
//        inputStream.connect(to: self)
//    }
//
//    /// See ConnectionContext.connection
//    public func connection(_ event: ConnectionEvent) {
//        onConnection(event)
//    }
//}

