/// Will receive call to `onOutput` once after passing an instance of `InputStream`
/// to `OutputStream.output(to:)`.
///
/// No further notifications will be received until `OutputRequest.requestOutput` is called.
///
/// After signaling demand:
/// - One or more invocations of `onInput` up to the maximum number defined
///   by `OutputRequest.requestOutput`
/// - Single invocation of `onError` or `InputStream.onClose` which signals a terminal
///   state after which no further events will be sent.
///
/// Demand can be signaled via `OutputRequest.requestOutput` whenever the `InputStream`
/// instance is capable of handling more.
public protocol InputStream {
    /// The type of element signaled.
    associatedtype Input

    /// Data notification sent by the `OutputStream` in response to requests to `OutputRequest.requestOutput`.
    ///
    /// - parameter input: the element signaled
    func onInput(_ next: Input) -> Future<Void>

    /// Failed terminal state.
    ///
    /// No further events will be sent even if `OutputRequest.requestOutput` is invoked again.
    ///
    /// - parameter error: the error signaled
    func onError(_ error: Error)


    /// Successful terminal state.
    ///
    /// No further events will be sent even if `OutputRequest.requestOutput` is invoked again.
    func onClose()
}

/// MARK: Any

/// Type-erased InputStream. This allows streams to hold pointers to their
/// downstream input streams without requiring that their stream class be generic
/// on a given downstream.
public final class AnyInputStream<Wrapped>: InputStream {
    /// See InputStream.Input
    public typealias Input = Wrapped

    /// On input event handler.
    private let onInputClosure: (Input) -> Future<Void>

    /// On error event handler.
    private let onErrorClosure: (Error) -> ()

    /// On close event handler.
    private let onCloseClosure: () -> ()

    /// Create a new any input stream from a wrapped stream.
    public init<S>(_ wrapped: S) where S: InputStream, S.Input == Wrapped {
        onInputClosure = wrapped.onInput
        onErrorClosure = wrapped.onError
        onCloseClosure = wrapped.onClose
    }

    /// See `InputStream.onInput(_:)`
    public func onInput(_ next: Input) -> Future<Void> {
        return onInputClosure(next)
    }

    /// See `InputStream.onError(_:)`
    public func onError(_ error: Error) {
        onErrorClosure(error)
    }

    /// See `InputStream.onClose()`
    public func onClose() {
        onCloseClosure()
    }
}
