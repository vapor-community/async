/// Allows for input to be enqueued by a push stream or user.
/// The next output will be returned as a Future for enqueued inputs.
public final class QueueStream<I, O>: Stream, ConnectionContext {
    /// See InputStream.Input
    public typealias Input = I

    /// See OutputStream.Output
    public typealias Output = O

    /// Queue of promised responses
    var inputQueue: [Promise<Input>]

    /// Queue of requests to be serialized
    var outputQueue: [Output]

    /// Accepts serialized requests
    var downstream: AnyInputStream<Output>?

    /// Serialized requests
    var remainingDownstreamRequests: UInt

    /// Parsed responses
    var upstream: ConnectionContext?

    /// Creates a new `QueueStream` stream
    public init() {
        self.inputQueue = []
        self.outputQueue = []
        self.remainingDownstreamRequests = 0
    }

    /// Enqueues a new output to the stream and returns
    /// a future that will be completed with the next input.
    public func enqueue(_ output: Output) -> Future<Input> {
        let promise = Promise(Input.self)
        self.outputQueue.append(output)
        self.inputQueue.append(promise)
        upstream?.request()
        update()
        return promise.future
    }

    @available(*, deprecated, renamed: "enqueue")
    public func queue(_ output: Output) -> Future<Input> {
        return enqueue(output)
    }

    /// Updates the stream's state. If there are outstanding
    /// downstream requests, they will be fulfilled.
    func update() {
        guard remainingDownstreamRequests > 0 else {
            return
        }
        while let output = outputQueue.popLast() {
            remainingDownstreamRequests -= 1
            downstream?.next(output)
        }
    }

    /// See ConnectionContext.connection
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .request(let count):
            let isSuspended = remainingDownstreamRequests == 0
            remainingDownstreamRequests += count
            if isSuspended { update() }
        case .cancel:
            /// FIXME: better cancel support
            remainingDownstreamRequests = 0
        }
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, S.Input == Output {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .connect(let upstream):
            self.upstream = upstream
            upstream.request(count: UInt(inputQueue.count))
        case .next(let input):
            let promise = inputQueue.popLast()!
            promise.complete(input)
            update()
        case .error(let error): downstream?.error(error)
        case .close:
            downstream?.close()
        }
    }
}
