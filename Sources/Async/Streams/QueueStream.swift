///// Enqueues a single input and waits for multiple output.
///// This is useful for situations where one request can lead
///// to multiple responses.
//public final class QueueStream<I, O>: Stream {
//    /// See `InputStream.Input`
//    public typealias Input = I
//
//    /// See `OutputStream.Output`
//    public typealias Output = O
//
//    /// Current downstrema input stream.
//    private var downstream: AnyInputStream<Output>?
//
//    /// Current downstream demand.
//    private var downstreamDemand: UInt
//
//    /// Queued output.
//    private var queuedOutput: [Output]
//
//    /// Queued input.
//    private var queuedInput: [QueueStreamInput<Input>]
//
//    /// Current input being handled.
//    private var currentInput: QueueStreamInput<Input>?
//
//    /// Create a new `AsymmetricQueueStream`.
//    public init() {
//        self.downstreamDemand = 0
//        self.queuedOutput = []
//        self.queuedInput = []
//    }
//
//    /// Enqueue the supplied output, specifying a closure that will determine
//    /// when the Input received is ready.
//    public func enqueue(_ output: [Output], onInput: @escaping (Input) throws -> Bool) -> Future<Void> {
//        let input = QueueStreamInput(onInput: onInput)
//        self.queuedInput.insert(input, at: 0)
//        for o in output {
//            self.queuedOutput.insert(o, at: 0)
//        }
//        update()
//        return input.promise.future
//    }
//
//    /// Enqueue the supplied output, returning a Future that will be completed
//    /// with the first received Input.
//    public func enqueue(_ output: Output) -> Future<Input> {
//        var capturedInput: Input?
//        return enqueue([output]) { input in
//            capturedInput = input
//            return true
//        }.map(to: Input.self) {
//            return capturedInput!
//        }
//    }
//
//    /// Updates internal state.
//    private func update() {
//        while downstreamDemand > 0 {
//            guard let output = queuedOutput.popLast() else {
//                break
//            }
//            downstreamDemand -= 1
//            downstream!.next(output, {}) // FIXME
//        }
//    }
//
////    /// See `ConnectionContext.connection`
////    public func connection(_ event: ConnectionEvent) {
////        switch event {
////        case .cancel: break // handle better
////        case .request(let count):
////            downstreamDemand += count
////            update()
////        }
////    }
//
//    /// See `InputStream.input`
//    public func input(_ event: InputEvent<I>) {
//        switch event {
//        case .close: downstream?.close()
//        case .error(let error): downstream?.error(error)
//        case .next(let input):
//            var context: QueueStreamInput<Input>
//            if let current = currentInput {
//                context = current
//            } else {
//                let next = queuedInput.popLast()!
//                currentInput = next
//                context = next
//            }
//
//            do {
//                if try context.onInput(input) {
//                    currentInput = nil
//                    context.promise.complete()
//                } else {
//                    upstream!.request(count: 1)
//                }
//            } catch {
//                currentInput = nil
//                context.promise.fail(error)
//            }
//        }
//    }
//
//    /// See `OutputStream.output`
//    public func output<S>(to inputStream: S) where S : InputStream, S.Input == Output {
//        downstream = .init(inputStream)
//        inputStream.connect(to: self)
//    }
//}
//
//struct QueueStreamInput<Input> {
//    var promise: Promise<Void>
//    var onInput: (Input) throws -> Bool
//
//    init(onInput: @escaping (Input) throws -> Bool) {
//        self.promise = .init()
//        self.onInput = onInput
//    }
//}

