/// A Stream that can be closed and can be listened to for closing
///
///
public protocol ClosableStream: BaseStream {
    /// A handler called when the stream closes.
    typealias CloseHandler = () -> ()

    /// Closes the connection
    func close()

    /// A function that gets called if the stream closes
    var onClose: CloseHandler? { get set }
}

extension ClosableStream {
    /// Closes the stream, calling the `onClose` handler.
    public func close() {
        onClose?()
    }

    /// Sets a CloseHandler callback on this stream.
    public func finally(_ onClose: @escaping CloseHandler) {
        self.onClose = onClose
    }
}
