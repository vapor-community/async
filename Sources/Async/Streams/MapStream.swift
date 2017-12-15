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
public final class MapStream<In, Out>: Stream, OutputRequest {
    /// See InputStream.Input
    public typealias Input = In

    /// See OutputStream.Output
    public typealias Output = Out

    /// Maps input to output
    public typealias MapClosure = (In) throws -> (Out)

    /// The stored map closure
    public let map: MapClosure

    /// Internal stream
    private var downstream: AnyInputStream?

    /// Current output request
    private var upstream: OutputRequest?

    /// Create a new Map stream with the supplied closure.
    public init(map: @escaping MapClosure) {
        self.map = map
    }

    public func requestOutput(_ count: UInt) {
        upstream?.requestOutput(count)
    }

    public func cancelOutput() {
        upstream?.cancelOutput()
    }

    /// See InputStream.onOutput
    public func onOutput(_ outputRequest: OutputRequest) {
        self.upstream = outputRequest
    }

    /// See InputStream.onInput
    public func onInput(_ input: In) {
        do {
            let output = try map(input)
            downstream?.unsafeOnInput(output)
            upstream?.requestOutput()
        } catch {
            onError(error)
        }
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        downstream?.onError(error)
    }

    /// See InputStream.onClose
    public func onClose() {
        downstream?.onClose()
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Out == S.Input {
        downstream = inputStream
        inputStream.onOutput(self)
    }

    private func update() {

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
