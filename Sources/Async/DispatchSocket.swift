/// A dispatch source compatible socket.
public protocol DispatchSocket {
    /// The file descriptor.
    var descriptor: Int32 { get }

    /// Reads a maxiumum of `max` bytes into the supplied mutable buffer.
    /// Returns the actual number of bytes read.
    func read(max: Int, into buffer: UnsafeMutableBufferPointer<UInt8>) throws -> Int

    /// Writes a maximum of `max` bytes from the supplied buffer.
    /// Returns the actual number of bytes written.
    func write(max: Int, from buffer: UnsafeBufferPointer<UInt8>) throws -> Int

    /// Closes the socket.
    func close()

    /// True if the socket is ready for normal use
    var isPrepared: Bool { get }

    /// Prepares the socket, called if isPrepared is false.
    func prepareSocket() throws
}

extension DispatchSocket {
    /// See DispatchSocket.isPrepared
    public var isPrepared: Bool { return true }

    /// See DispatchSocket.prepareSocket
    public func prepareSocket() throws {}
}
