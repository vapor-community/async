/// Drains signals into the supplied closures.
/// note: This stream will _not_ forward signals for
/// which it has draining closures set to connected streams.
/// Signals for which no closures are set will continue to be forwarded.
public final class DrainStream<Draining>: Stream {
    /// See OutputStream.Output
    public typealias Output = Draining

    /// See InputStream.Input
    public typealias Input = Draining

    /// The current outupt request
    /// `nil` if the stream has not yet been connected.
    var outputRequest: OutputRequest?

    /// Handles input
    public typealias OnInput = (Input, OutputRequest) throws -> ()

    /// Handles errors
    public typealias OnError = (Error) -> ()

    /// Handles close
    public typealias OnClose = () -> ()

    /// See OnDrainingInput
    private let onInputClosure: OnInput?

    /// See OnError
    private let onErrorClosure: OnError?

    /// See OnClose
    private let onCloseClosure: OnClose?

    /// Connected stream
    private var connected: BasicStream<Draining>

    /// Initial output request size
    private let initialOutputRequest: UInt

    /// Create a new drain stream
    public init(
        _ output: Output.Type = Output.self,
        onInput: OnInput? = nil,
        onError: OnError? = nil,
        onClose: OnClose? = nil,
        initialOutputRequest: UInt
    ) {
        outputRequest = nil
        onInputClosure = onInput
        onErrorClosure = onError
        onCloseClosure = onClose
        connected = .init()
        self.initialOutputRequest = initialOutputRequest
    }

    /// See InputStream.onOutput
    public func onOutput(_ outputRequest: OutputRequest) {
        self.outputRequest = outputRequest
        outputRequest.requestOutput(initialOutputRequest)
    }

    /// See InputStream.onInput
    public func onInput(_ input: Input) {
        if let drainInput = onInputClosure {
            if let outputRequest = self.outputRequest {
                do {
                    try drainInput(input, outputRequest)
                } catch {
                    onError(error)
                }
            }
        } else {
            connected.onInput(input)
        }
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        if let drainError = onErrorClosure {
            drainError(error)
        } else {
            connected.onError(error)
        }
    }

    /// See InputStream.onClose
    public func onClose() {
        if let drainClose = onCloseClosure {
            drainClose()
        } else {
            connected.onClose()
        }
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Draining == S.Input {
        connected.output(to: inputStream)
    }
}

// MARK: Convenience

extension OutputStream {
    /// Drains the output stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func drain(_ initialOutputRequest: UInt = 1, onInput: @escaping DrainStream<Output>.OnInput) -> DrainStream<Output> {
        let drain = DrainStream(Output.self, onInput: onInput, initialOutputRequest: initialOutputRequest)
        return stream(to: drain)
    }

    /// Drains the output stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func `catch`(onError: @escaping DrainStream<Output>.OnError) -> DrainStream<Output> {
        let drain = DrainStream(Output.self, onError: onError, initialOutputRequest: 0)
        return stream(to: drain)
    }

    /// The supplied closure will be called when this stream closes.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    @discardableResult
    public func finally(onClose: @escaping BasicStream<Void>.OnClose) -> DrainStream<Output> {
        let drain = DrainStream(Output.self, onClose: onClose, initialOutputRequest: 0)
        return stream(to: drain)
    }
}
