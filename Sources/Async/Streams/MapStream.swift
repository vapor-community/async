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
public final class MapStream<In, Out>: Stream {
    /// See InputStream.Input
    public typealias Input = In

    /// See OutputStream.Output
    public typealias Output = Out

    /// Maps input to output
    public typealias MapClosure = (In) throws -> (Out)

    /// The stored map closure
    public let map: MapClosure

    /// The upstream stream, if set
    private var upstream: ConnectionContext?

    /// Internal stream
    private var downstream: AnyInputStream<Out>?

    /// Create a new Map stream with the supplied closure.
    public init(map: @escaping MapClosure) {
        self.map = map
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<In>) {
        switch event {
        case .next(let i):
            do {
                let output = try map(i)
                downstream?.next(output)
            } catch {
                downstream?.error(error)
            }
        case .connect(let upstream):
            self.upstream = upstream
            downstream?.connect(to: upstream)
        case .error(let e): downstream?.error(e)
        case .close: downstream?.close()
        }
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Out == S.Input {
        downstream = AnyInputStream(inputStream)
        if let upstream = upstream {
            inputStream.connect(to: upstream)
        }
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
    public func map<T>(
        map: @escaping MapStream<Output, T>.MapClosure
    ) -> MapStream<Output, T> {
        let map = MapStream(map: map)
        return stream(to: map)
    }
}
