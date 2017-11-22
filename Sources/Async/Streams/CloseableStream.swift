/// A Stream that can be closed and can be listened to for closing
public protocol ClosableStream: BaseStream {
    /// A handler called when the stream closes.
    typealias OnClose = () -> ()

    /// Closes the connection
    func close()

    /// A function that gets called if the stream closes
    var onClose: OnClose? { get set }
}

extension ClosableStream {
    /// Closes the stream, calling the `onClose` handler.
    public func notifyClosed() {
        onClose?()
    }

    /// Sets a CloseHandler callback on this stream.
    public func finally(onClose: @escaping OnClose) {
        self.onClose = onClose
    }
}
