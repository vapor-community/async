/// Drains signals into the supplied closures.
///
/// This stream will _not_ forward signals to connected streams
/// for which it has draining closures set.
///
/// Signals for which no closures are set will continue to be forwarded.
public final class DrainStream<Draining>: InputStream {
    /// See InputStream.Input
    public typealias Input = Draining

    /// Handles upstream connected
    public typealias OnOutput = (OutputRequest) -> ()

    /// Handles input
    public typealias OnInput = (Input) throws -> ()

    /// Handles errors
    public typealias OnError = (Error) -> ()

    /// Handles close
    public typealias OnClose = () -> ()

    /// See OnOutput
    private var onOutputClosure: OnOutput?

    /// See OnInput
    private var onInputClosure: OnInput?

    /// See OnError
    private var onErrorClosure: OnError?

    /// See OnClose
    private var onCloseClosure: OnClose?

    /// Create a new drain stream
    public init(
        _ output: Input.Type = Input.self,
        onOutput: OnOutput? = nil,
        onInput: OnInput? = nil,
        onError: OnError? = nil,
        onClose: OnClose? = nil
    ) {
        onOutputClosure = onOutput
        onInputClosure = onInput
        onErrorClosure = onError
        onCloseClosure = onClose
    }

    /// See InputStream.onOutput
    public func onOutput(_ outputRequest: OutputRequest) {
        if let onOutput = self.onOutputClosure {
            onOutput(outputRequest)
        }
    }

    /// See InputStream.onInput
    public func onInput(_ input: Input) {
        if let drainInput = onInputClosure {
            do {
                try drainInput(input)
            } catch {
                onError(error)
            }
        }
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        if let drainError = onErrorClosure {
            drainError(error)
        }
    }

    /// See InputStream.onClose
    public func onClose() {
        if let drainClose = onCloseClosure {
            drainClose()
        }
    }
}

// MARK: Convenience

extension OutputStream {
    /// Drains the output stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func drain(onOutput: @escaping DrainStream<Output>.OnOutput) -> DrainStream<Output> {
        let drain = DrainStream(Output.self, onOutput: onOutput)
        return stream(to: drain)
    }
}

extension DrainStream {
    /// Drains the output stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func output(onInput: @escaping DrainStream<Input>.OnInput) -> DrainStream<Input> {
        self.onInputClosure = onInput
        return self
    }

    /// Drains the error stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func `catch`(onError: @escaping DrainStream<Input>.OnError) -> DrainStream<Input> {
        self.onErrorClosure = onError
        return self
    }

    /// Drains the close stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func finally(onClose: @escaping DrainStream<Void>.OnClose) {
        self.onCloseClosure = onClose
    }
}
