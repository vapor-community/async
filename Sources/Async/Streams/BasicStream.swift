/// A basic, generic stream implementation.
public final class ClosureStream<Data>: Stream, OutputRequest {
    /// See InputStream.Input
    public typealias Input = Data

    /// See OutputStream.Output
    public typealias Output = Data

    /// Handles input
    public typealias OnInput = (Input) -> ()

    /// Handles errors
    public typealias OnError = (Error) -> ()

    /// Handles close
    public typealias OnClose = () -> ()

    /// Handles output
    public typealias OnOutput = (OutputRequest) -> ()

    /// Handles output request
    public typealias OnRequest = (UInt) -> ()

    /// Handles cancellation
    public typealias OnCancel = () -> ()

    /// Handles outputTo
    public typealias OutputTo = (AnyInputStream) -> ()

    /// See OnInput
    public var onInputClosure: OnInput

    /// See OnError
    public var onErrorClosure: OnError

    /// See OnClose
    public var onCloseClosure: OnClose

    /// See OnOutput
    public var onOutputClosure: OnOutput

    /// See OnRequest
    public var onRequestClosure: OnRequest

    /// See OnCancel
    public var onCancelClosure: OnCancel

    public var outputToClosure: OutputTo

    /// Create a new BasicStream generic on the supplied type.
    public init(
        _ data: Data.Type = Data.self,
        onInput: @escaping OnInput,
        onError: @escaping OnError,
        onClose: @escaping OnClose,
        onOutput: @escaping OnOutput,
        onRequest: @escaping OnRequest,
        onCancel: @escaping OnCancel,
        outputTo: @escaping OutputTo
    ) {
        onInputClosure = onInput
        onErrorClosure = onError
        onCloseClosure = onClose
        onOutputClosure = onOutput
        onRequestClosure = onRequest
        onCancelClosure = onCancel
        outputToClosure = outputTo
    }

    /// See InputStream.onInput
    public func onInput(_ input: Data) {
        onInputClosure(input)
    }

    /// See InputStream.onError
    public func onError(_ error: Error) {
        onErrorClosure(error)
    }

    /// See InputStream.onClose
    public func onClose() {
        onCloseClosure()
    }

    /// See InputStream.onOutput
    public func onOutput(_ outputRequest: OutputRequest) {
        onOutputClosure(outputRequest)
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S : InputStream, Data == S.Input {
        outputToClosure(inputStream)
        inputStream.onOutput(self)
    }

    /// See OutputRequest.onRequest
    public func requestOutput(_ count: UInt) {
        onRequestClosure(count)
    }

    /// See OutputRequest.onCancel
    public func cancelOutput() {
        onCancelClosure()
    }
}
