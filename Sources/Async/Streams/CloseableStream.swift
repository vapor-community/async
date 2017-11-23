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
    
    /// Assign a closeable stream to be notified (closed)
    /// when this stream closes.
    func onClose(_ onClose: ClosableStream)
}

extension ClosableStream {
    /// The supplied closure will be called when this stream closes.
    public func finally(onClose: @escaping BasicStream<Void>.OnClose) {
        let stream = BasicStream<Void>()
        stream.closeClosure = onClose
        self.onClose(stream)
    }
}
