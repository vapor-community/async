/// Drains signals into the supplied closures.
///
/// This stream will _not_ forward signals to connected streams
/// for which it has draining closures set.
///
/// Signals for which no closures are set will continue to be forwarded.
public final class DrainStream<Draining>: InputStream {
    /// See InputStream.Input
    public typealias Input = Draining

    /// Handles upstream connectect
    public var upstream: ConnectionContext?

    /// Handles input
    public typealias OnInput = (Input, ConnectionContext) throws -> ()
    private var onInputClosure: OnInput?

    /// Handles errors
    public typealias OnError = (Error) -> ()
    private var onErrorClosure: OnError?

    /// Handles close
    public typealias OnClose = () -> ()
    private var onCloseClosure: OnClose?

    /// Create a new drain stream
    public init(
        _ output: Input.Type = Input.self,
        onInput: OnInput? = nil,
        onError: OnError? = nil,
        onClose: OnClose? = nil
    ) {
        onInputClosure = onInput
        onErrorClosure = onError
        onCloseClosure = onClose
    }

    /// See InputStream.onInput
    public func input(_ event: InputEvent<Draining>) {
        switch event {
        case .connect(let upstream): self.upstream = upstream
        case .next(let input): do { try onInputClosure?(input, upstream!) } catch { onErrorClosure?(error) }
        case .error(let error): onErrorClosure?(error)
        case .close: onCloseClosure?()
        }
    }
}

// MARK: Convenience

extension OutputStream {
    /// Drains the output stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func drain(onInput: @escaping DrainStream<Output>.OnInput) -> DrainStream<Output> {
        let drain = DrainStream(Output.self, onInput: onInput)
        return stream(to: drain)
    }
}

extension DrainStream {
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
    public func finally(onClose: @escaping DrainStream<Void>.OnClose) -> ConnectionContext {
        self.onCloseClosure = onClose
        return self.upstream!
    }
}
