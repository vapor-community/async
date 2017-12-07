/// A `OutputRequest` represents a one-to-one lifecycle of a `InputStream` subscribing to a `OutputStream`.
///
/// It can only be used once by a single `InputStream`.
///
/// It is used to both signal desire for data and cancel demand (and allow resource cleanup).
public protocol OutputRequest {
    /// No events will be sent by a `OutputStream` until demand is signaled via this method.
    ///
    /// It can be called however often and whenever needed—but the outstanding cumulative demand
    /// must never exceed `UInt.max`. An outstanding cumulative demand of `UInt.max` may be treated
    /// by the `OutputStream` as "effectively unbounded".
    ///
    /// Whatever has been requested can be sent by the `OutputStream` so only signal demand
    /// for what can be safely handled.
    ///
    /// A `OutputStream` can send less than is requested if the stream ends but then must emit either
    /// `InputStream.onError` or `InputStream.onClose`.
    ///
    /// - parameter count: the strictly positive number of elements to requests to the upstream `OutputStream`
    func requestOutput(_ count: UInt)

    /// Request the `OutputStream` to stop sending data and clean up resources.
    ///
    /// Data may still be sent to meet previously signalled demand after calling cancel.
    func cancelOutput()
}

extension OutputRequest {
    /// Requests one output.
    /// See OutputRequest.requestOutput
    public func requestOutput() {
        requestOutput(1)
    }
}
