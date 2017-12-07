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

    /// Internal stream
    internal var connected: BasicStream<Out>

    /// Current output request
    private var outputRequest: OutputRequest?

    /// Initial output request size
    private let initialOutputRequest: UInt

    /// Create a new Map stream with the supplied closure.
    public init(
        map: @escaping MapClosure,
        initialOutputRequest: UInt
    ) {
        self.map = map
        self.initialOutputRequest =  initialOutputRequest
        connected = .init()
    }

    /// See InputStream.onOutput
    public func onOutput(_ outputRequest: OutputRequest) {
        self.outputRequest = outputRequest
        outputRequest.requestOutput(initialOutputRequest)
    }

    /// See InputStream.onInput
    public func onInput(_ input: In) {
        do {
            let output = try map(input)
            print(connected)
            connected.onInput(output)
            outputRequest?.requestOutput()
        } catch {
            onError(error)
        }
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        connected.onError(error)
    }

    /// See InputStream.onClose
    public func onClose() {
        connected.onClose()
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Out == S.Input {
        connected.output(to: inputStream)
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
        _ initialOutputRequest: UInt = 1,
        map: @escaping MapStream<Output, T>.MapClosure
    ) -> MapStream<Output, T> {
        let map = MapStream(map: map, initialOutputRequest: initialOutputRequest)
        return stream(to: map)
    }
}
