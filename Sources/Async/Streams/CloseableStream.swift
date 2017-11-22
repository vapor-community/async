/// A Stream that can be closed and can be listened to for closing
///
/// This stream is unique in that it is both an:
///     - input: subscribes to close events
///     - output: publishes close events
///
/// note the subtle difference between the two `onClose` methods.
public protocol ClosableStream: BaseStream {
    /// Closes the stream
    func close()
    
    /// Assign a new closeable stream to be notified
    /// when this stream closes.
    func onClose(_ onClose: ClosableStream)
}

extension ClosableStream {
    /// Sets a CloseHandler callback on this stream.
    public func finally(onClose: @escaping BasicStream<Void>.OnClose) {
        let stream = BasicStream<Void>()
        stream.closeClosure = onClose
        self.onClose(stream)
    }
}
