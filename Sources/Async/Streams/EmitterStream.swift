/// A basic output stream.
///
/// Example using a number emitter and map stream to square numbers:
///
///     let numberEmitter = EmitterStream(Int.self)
///     let squareMapStream = MapStream<Int, Int> { int in
///         return int * int
///     }
///
///     var squares: [Int] = []
///
///     numberEmitter.stream(to: squareMapStream).drain { square in
///         squares.append(square)
///     }
///
///     numberEmitter.emit(1)
///     numberEmitter.emit(2)
///     numberEmitter.emit(3)
///
///     print(squares) // [1, 4, 9]
///
public final class EmitterStream<Out>: OutputStream, ClosableStream {
    /// See OutputStream.Output
    public typealias Output = Out

    /// Internal stream
    internal var _stream: BasicStream<Out>

    /// Create a new emitter stream.
    public init(_ type: Out.Type = Out.self) {
        _stream = .init()
    }


    /// See OutputStream.onOutput
    public func onOutput<I>(_ input: I) where I : InputStream, Out == I.Input {
        _stream.onOutput(input)
    }

    /// See ClosableStream.close
    public func close() {
        print("emitter close")
        _stream.close()
    }

    /// See ClosableStream.onClose
    public func onClose(_ close: ClosableStream) {
        print("emitter on close")
        _stream.onClose(close)
    }

    /// Emits an output.
    public func emit(_ output: Output) {
        _stream.onInput(output)
    }
}
