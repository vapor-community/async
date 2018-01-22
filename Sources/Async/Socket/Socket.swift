/// A dispatch source compatible socket.
public protocol Socket {
    /// The file descriptor.
    var descriptor: Int32 { get }

    /// Reads a maxiumum of `buffer.count` bytes into the supplied mutable buffer.
    /// Returns the actual number of bytes read.
    func read(into buffer: UnsafeMutableBufferPointer<UInt8>) throws -> SocketReadStatus

    /// Writes a maximum of `buffer.count` bytes from the supplied buffer.
    /// Returns the actual number of bytes written.
    func write(from buffer: UnsafeBufferPointer<UInt8>) throws -> SocketWriteStatus

    /// Closes the socket.
    func close()
}

/// Returned by calls to `Socket.read`
public enum SocketReadStatus {
    /// The socket read normally.
    /// Note: count == 0 indicates the socket closed.

    case read(count: Int)
    /// The internal socket buffer is empty,
    /// this call would have blocked had this
    /// socket not been set to non-blocking mode.
    ///
    /// Use an event loop to notify you when this socket
    /// is ready to be read from again.
    ///
    /// Note: this is not an error.
    case wouldBlock
}

/// Returned by calls to `Socket.write`
public enum SocketWriteStatus {
    /// The socket wrote normally.
    /// Note: count == 0 indicates the socket closed.
    case wrote(count: Int)

    /// The internal socket buffer is full,
    /// this call would have blocked had this
    /// socket not been set to non-blocking mode.
    ///
    /// Use an event loop to notify you when this socket
    /// is ready to be written to again.
    ///
    /// Note: this is not an error.
    case wouldBlock
}
