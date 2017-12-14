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
public protocol InputStream: AnyInputStream {
    /// The type of element signaled.
    associatedtype Input

    /// Data notification sent by the `OutputStream` in response to requests to `OutputRequest.requestOutput`.
    ///
    /// - parameter input: the element signaled
    func onInput(_ input: Input)
}

extension InputStream {
    /// Implement by force casting to the supported input type.
    /// See AnyInputStream.unsafeOnInput
    public func unsafeOnInput(_ input: Any) {
        return onInput(input as! Input)
    }
}

/// Type-erased InputStream. This allows streams to hold pointers to their
/// downstream input streams without requiring that their stream class be generic
/// on a given downstream.
public protocol AnyInputStream: class {
    /// Invoked after calling `OutputStream.output(to:)`.
    ///
    /// No data will start flowing until `OutputRequest.requestOutput` is invoked.
    ///
    /// It is the responsibility of this `InputStream` instance to call
    /// `OutputRequest.requestOutput` whenever more data is wanted.
    ///
    /// The `OutputStream` will send notifications only in response to `OutputRequest.requestOutput`.
    ///
    /// - parameter outputRequest: `OutputRequest` that allows requesting data via `OutputRequest.requestOutput`
    func onOutput(_ outputRequest: OutputRequest)

    /// Data notification sent by the `OutputStream` in response to requests to `OutputRequest.requestOutput`.
    ///
    /// - parameter input: the element signaled
    func unsafeOnInput(_ input: Any)

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
