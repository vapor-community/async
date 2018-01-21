///// A basic output stream.
/////
///// Example using a number emitter and map stream to square numbers:
/////
/////     let numberEmitter = EmitterStream(Int.self)
/////     let squareMapStream = MapStream<Int, Int> { int in
/////         return int * int
/////     }
/////
/////     var squares: [Int] = []
/////
/////     numberEmitter.stream(to: squareMapStream).drain { square in
/////         squares.append(square)
/////     }
/////
/////     numberEmitter.emit(1)
/////     numberEmitter.emit(2)
/////     numberEmitter.emit(3)
/////
/////     print(squares) // [1, 4, 9]
/////
//public final class EmitterStream<Emitted>: OutputStream {
//    /// See OutputStream.Output
//    public typealias Output = Emitted
//
//    /// The requests that will receive emitted values
//    private var outputs: [EmitterOutputRequest<Emitted>]
//
//    public init(_ emitted: Emitted.Type = Emitted.self) {
//        self.outputs = []
//    }
//
//    /// See OutputStream.output
//    public func output<S>(to inputStream: S) where S : InputStream, Emitted == S.Input {
//        let request = EmitterOutputRequest<Emitted>(inputStream)
//        outputs.append(request)
//        inputStream.connect(to: request)
//    }
//
//    /// Emits an item to the stream
//    public func emit(_ emitted: Emitted) {
//        outputs = outputs.filter { !$0.isCancelled }
//        for output in outputs {
//            if output.remaining > 0 {
//                output.remaining -= 1
//                output.stream.next(emitted)
//            }
//        }
//    }
//
//    /// Closes the emitter stream
//    public func close() {
//        for output in outputs {
//            output.stream.close()
//        }
//    }
//}
//
//fileprivate final class EmitterOutputRequest<Emitted>: ConnectionContext {
//    /// Connected stream
//    var stream: AnyInputStream<Emitted>
//
//    /// Remaining requested output
//    var remaining: UInt
//
//    /// If true, the output request is cancelled
//    var isCancelled: Bool
//
//    /// Create a new emitter output request
//    init<S>(_ inputStream: S) where S: InputStream, Emitted == S.Input {
//        remaining = 0
//        isCancelled = false
//        stream = AnyInputStream(inputStream)
//    }
//
//    /// See ConnectionContext.connection
//    func connection(_ event: ConnectionEvent) {
//        switch event {
//        case .cancel: isCancelled = true
//        case .request(let count): remaining += count
//        }
//    }
//}

