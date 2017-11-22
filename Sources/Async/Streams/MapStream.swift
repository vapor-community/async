/// A basic stream implementation that maps input
/// through a closure.
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
/// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#transforming-streams-without-an-intermediary-stream)
public final class MapStream<In, Out>: Stream, ClosableStream {
    /// See InputStream.Input
    public typealias Input = In

    /// See OutputStream.Output
    public typealias Output = Out

    /// Internal stream
    internal var _stream: BasicStream<Out>

    /// Maps input to output
    public typealias MapClosure = (In) throws -> (Out)

    /// The stored map closure
    public let map: MapClosure

    /// See InputStream.onInput
    public func onInput(_ input: In) {
        do {
            try _stream.onInput(map(input))
        } catch {
            onError(error)
        }
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        _stream.onError(error)
    }

    /// See OutputStream.onOutput
    public func onOutput<I>(_ input: I) where I : InputStream, Out == I.Input {
        _stream.onOutput(input)
    }

    /// See CloseableStream.onClose
    public func onClose(_ onClose: ClosableStream) {
        print("map on close")
        _stream.onClose(onClose)
    }

    /// See CloseableStream.close
    public func close() {
        print("map close")
        _stream.close()
    }

    /// Create a new Map stream with the supplied closure.
    public init(map: @escaping MapClosure) {
        self.map = map
        _stream = .init()
    }
}

extension OutputStream {
    /// Transforms the output of one stream (as the input of the transform) to another output
    ///
    /// An example of mapping ints to strings:
    ///
    ///     let integerStream: BasicOutputStream<Int>
    ///     let stringSteam:   MapStream<Int, String> = integerStream.map { integer in
    ///         return integer.description
    ///     }
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#transforming-streams-without-an-intermediary-stream)
    public func map<T>(_ transform: @escaping ((Output) throws -> (T))) -> MapStream<Output, T> {
        let stream = MapStream(map: transform)
        return self.stream(to: stream)
    }
}
