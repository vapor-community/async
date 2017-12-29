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
    public typealias OnConnect = (ConnectionContext) -> ()
    private var onConnectClosure: OnConnect?

    /// Handles input
    public typealias OnInput = (ConnectionContext, Input) throws -> ()
    private var onInputClosure: OnInput?

    /// Handles errors
    public typealias OnError = (Error) -> ()
    private var onErrorClosure: OnError?

    /// Handles close
    public typealias OnClose = () -> ()
    private var onCloseClosure: OnClose?
    
    private var upstream: ConnectionContext?

    /// Create a new drain stream
    public init(
        _ output: Input.Type = Input.self,
        onConnect: OnConnect? = nil,
        onInput: OnInput? = nil,
        onError: OnError? = nil,
        onClose: OnClose? = nil
    ) {
        onConnectClosure = onConnect
        onInputClosure = onInput
        onErrorClosure = onError
        onCloseClosure = onClose
    }

    /// See InputStream.onInput
    public func input(_ event: InputEvent<Draining>) {
        switch event {
        case .connect(let event):
            self.upstream = event
            onConnectClosure?(event)
        case .next(let input): do { try onInputClosure?(upstream!, input) } catch { onErrorClosure?(error) }
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
    public func drain(onConnect: @escaping DrainStream<Output>.OnConnect) -> DrainStream<Output> {
        let drain = DrainStream(Output.self, onConnect: onConnect)
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
