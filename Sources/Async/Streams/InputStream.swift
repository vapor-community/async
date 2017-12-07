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

    /// Invoked after calling `OutputStream.output(to:)`.
    ///
    /// No data will start flowing until `OutputRequest.requestOutput` is invoked.
    ///
    /// It is the responsibility of this `InputStream` instance to call
    /// `OutputRequest.requestOutput` whenever more data is wanted.
    ///
    /// The `OutputStream` will send notifications only in response to `OutputRequest.requestOutput`.
    ///
    /// - parameter subscription: `OutputRequest` that allows requesting data via `OutputRequest.requestOutput`
    func onOutput(_ outputRequest: OutputRequest)

    /// Data notification sent by the `OutputStream` in response to requests to `OutputRequest.requestOutput`.
    ///
    /// - parameter input: the element signaled
    func onInput(_ input: Input)

    /// Failed terminal state.
    ///
    /// No further events will be sent even if `OutputRequest.requestOutput` is invoked again.
    ///
    /// - parameter error: the throwable signaled
    func onError(_ error: Error)

    /// Successful terminal state.
    ///
    /// No further events will be sent even if `OutputRequest.requestOutput` is invoked again.
    func onClose()
}
