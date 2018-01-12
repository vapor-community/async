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
    private var buffers: SocketBuffers

    /// Stores read event source.
    private var readSource: EventSource?

    /// Use a basic stream to easily implement our output stream.
    private var downstream: AnyInputStream<UnsafeBufferPointer<UInt8>>?

    /// The amount of requested output remaining
    private var requestedOutputRemaining: UInt
    
    /// A strong reference to the current eventloop
    private var eventLoop: EventLoop

    /// True if the socket has returned that it would block
    /// on the previous call
    private var socketIsEmpty: Bool

    internal init(socket: Socket, on worker: Worker) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        self.buffers = SocketBuffers(count: 4, capacity: 4096)
        self.requestedOutputRemaining = 0
        self.socketIsEmpty = true
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
        case .request(let count):
            assert(count == 1)
            buffers.releaseReadable()
            requestedOutputRemaining += count
            update()
        case .cancel: close()
        }
    }

    private func update() {
        guard requestedOutputRemaining > 0 else {
            return
        }

        while buffers.canRead && requestedOutputRemaining > 0 {
            let buffer = buffers.leaseReadable()
            requestedOutputRemaining -= 1
            downstream?.next(buffer)
        }

        if buffers.canWrite, !socketIsEmpty {
            readData()
        }
    }

    /// Cancels reading
    public func close() {
        socket.close()
        downstream?.close()
        readSource = nil
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

        let buffer = buffers.nextWritable()
        let read: SocketReadStatus
        do {
            read = try socket.read(into: buffer)
        } catch {
            // any errors that occur here cannot be thrown,
            //selfso send them to stream error catcher.
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
            buffers.addReadable(view)
        case .wouldBlock:
            socketIsEmpty = true
        }

        update()
    }

    /// Called when the read source signals.
    private func readSourceSignal(isCancelled: Bool) {
        guard !isCancelled else {
            close()
            return
        }
        socketIsEmpty = false
        update()
    }

    /// Deallocated the pointer buffer
    deinit {
        buffers.cleanup()
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func source(on eventLoop: Worker) -> SocketSource<Self> {
        return .init(socket: self, on: eventLoop)
    }
}

