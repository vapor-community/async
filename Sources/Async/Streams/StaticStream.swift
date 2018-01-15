/// A static stream of data, capable of outputting to one downstream.
public final class StaticOutputStream<O>: OutputStream, ConnectionContext {
    /// See `OutputStream.Output`
    public typealias Output = O

    /// Current downstream.
    private var downstream: AnyInputStream<Output>?

    /// Remaining data
    private var data: [Output]

    /// Creates a new `StaticStream` that will output the supplied data.
    public init(data: [Output]) {
        self.data = data.reversed()
    }

    /// See `ConnectionContext.connection`
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .cancel:
            data = []
        case .request(var count):
            stream: while count > 0 {
                count -= 1
                if let data = self.data.popLast() {
                    downstream!.next(data)
                } else {
                    // out of data
                    break stream
                }
            }
        }
    }

    /// See `OutputStream.Output`
    public func output<S>(to inputStream: S) where S: Async.InputStream, S.Input == Output {
        self.downstream = .init(inputStream)
        inputStream.connect(to: self)
    }

}
