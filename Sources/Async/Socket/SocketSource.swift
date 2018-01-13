import Dispatch
import Foundation

/// Data stream wrapper for a dispatch socket.
public final class SocketSource<Socket>: OutputStream, ConnectionContext
    where Socket: Async.Socket
{
    /// See OutputStream.Output
    public typealias Output = UnsafeBufferPointer<UInt8>

    /// The client stream's underlying socket.
    public var socket: Socket

    /// Bytes from the socket are read into this buffer.
    /// Views into this buffer supplied to output streams.
    private var buffer: UnsafeMutableBufferPointer<UInt8>

    /// Stores read event source.
    private var readSource: EventSource?

    /// Use a basic stream to easily implement our output stream.
    private var downstream: AnyInputStream<UnsafeBufferPointer<UInt8>>?

    /// The amount of requested output remaining
    private var requestedOutputRemaining: UInt
    
    /// A strong reference to the current eventloop
    private var eventLoop: EventLoop

    internal init(socket: Socket, on worker: Worker, bufferSize: Int) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        self.requestedOutputRemaining = 0
        self.buffer = .init(start: .allocate(capacity: bufferSize), count: bufferSize)
        let readSource = self.eventLoop.onReadable(descriptor: socket.descriptor, readSourceSignal)
        readSource.resume()
        self.readSource = readSource
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: Async.InputStream, S.Input == UnsafeBufferPointer<UInt8> {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }

    /// See ConnectionContext.connection
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .request(let count): requestedOutputRemaining += count
        case .cancel: close()
        }
    }

    /// Cancels reading
    public func close() {
        socket.close()
        downstream?.close()
        // readSource = nil
        downstream = nil
    }

    /// Reads data and outputs to the output stream
    /// important: the socket _must_ be ready to read data
    /// as indicated by a read source.
    private func readData() {
        // prepare the socket if necessary
        guard socket.isPrepared else {
            do {
                try socket.prepareSocket()
            } catch {
                downstream?.error(error)
            }
            return
        }

        let read: SocketReadStatus
        do {
            read = try socket.read(into: buffer)
        } catch {
            // any errors that occur here cannot be thrown,
            // so send them to stream error catcher.
            downstream?.error(error)
            return
        }

        switch read {
        case .read(let count):
            guard count > 0 else {
                close()
                return
            }

            let view = UnsafeBufferPointer<UInt8>(start: buffer.baseAddress, count: count)
            requestedOutputRemaining -= 1
            downstream!.next(view)
        case .wouldBlock: fatalError()
        }
    }

    /// Called when the read source signals.
    private func readSourceSignal(isCancelled: Bool) {
        guard !isCancelled else {
            close()
            return
        }

        guard requestedOutputRemaining > 0 else {
            return
        }

        readData()
    }

    /// Deallocated the pointer buffer
    deinit {
        buffer.baseAddress?.deallocate(capacity: buffer.count)
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func source(on eventLoop: Worker, bufferSize: Int = 4096) -> SocketSource<Self> {
        return .init(socket: self, on: eventLoop, bufferSize: bufferSize)
    }
}

