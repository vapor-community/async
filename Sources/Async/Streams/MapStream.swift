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
public final class MapStream<In, Out>: TranscribingStream {
    /// See InputStream.Input
    public typealias Input = In

    /// See OutputStream.Output
    public typealias Output = Out

    /// The stored map closure
    public let map: (In) throws ->  Future<Out>

    /// Internal stream
    private var downstream: AnyInputStream<Out>?

    /// Create a new Map stream with the supplied closure.
    public init(map: @escaping (In) throws -> Future<Out>) {
        self.map = map
    }

    /// See `TranscribingStream.transcribe(_:)`
    public func transcribe(_ input: In) throws -> Future<Out> {
        return try map(input)
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
        to type: T.Type,
        map: @escaping (Output) throws -> T
    ) -> TranscribingStreamWrapper<MapStream<Output, T>> {
        let map = MapStream(map: { output in
            return try Future(map(output))
        }).stream()
        return stream(to: map)
    }

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
    public func flatMap<T>(
        to type: T.Type,
        map: @escaping (Output) throws -> Future<T>
    ) -> TranscribingStreamWrapper<MapStream<Output, T>> {
        let map = MapStream(map: map).stream()
        return stream(to: map)
    }
}
