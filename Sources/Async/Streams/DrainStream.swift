/// Drains signals into the supplied closures.
///
/// This stream will _not_ forward signals to connected streams
/// for which it has draining closures set.
///
/// Signals for which no closures are set will continue to be forwarded.
public final class DrainStream<Draining>: InputStream {
    /// See InputStream.Input
    public typealias Input = Draining

    /// Handles input
    public typealias OnInput = (Input) throws -> Future<Void>
    private var onInputClosure: OnInput

    /// Handles errors
    public typealias OnError = (Error) -> ()
    private var onErrorClosure: OnError

    /// Handles close
    public typealias OnClose = () -> ()
    private var onCloseClosure: OnClose

    /// Create a new drain stream
    public init(
        _ output: Input.Type = Input.self,
        onInput: @escaping OnInput,
        onError: @escaping OnError,
        onClose: @escaping OnClose
    ) {
        onInputClosure = onInput
        onErrorClosure = onError
        onCloseClosure = onClose
    }

    /// See `InputStream.onInput(_:)`
    public func onInput(_ next: Input) -> Future<Void> {
        do {
            return try onInputClosure(next)
        } catch {
            onError(error)
            return .done
        }
    }

    /// See `InputStream.onError(_:)`
    public func onError(_ error: Error) {
        onErrorClosure(error)
    }

    /// See `InputStream.onClose(_:)`
    public func onClose() {
        onCloseClosure()
    }
}

// MARK: Convenience

extension OutputStream {
    /// Drains the output stream into a closure.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#draining-streams)
    public func drain(onInput: @escaping DrainStream<Output>.OnInput) -> DrainStream<Output> {
        let drain = DrainStream(Output.self, onInput: onInput, onError: { _ in }, onClose: { })
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
    public func finally(onClose: @escaping DrainStream<Void>.OnClose) -> DrainStream<Input> {
        self.onCloseClosure = onClose
        return self
    }
}
