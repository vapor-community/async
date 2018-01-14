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

    /// Creates a new `SocketSource`
    internal init(socket: Socket, on worker: Worker, bufferSize: Int) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        self.requestedOutputRemaining = 0
        self.buffer = .init(start: .allocate(capacity: bufferSize), count: bufferSize)
        let readSource = self.eventLoop.onReadable(
            descriptor: socket.descriptor,
            readSourceSignal
        )
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
            assert(count == 1, "SocketSource downstream must request 1 buffer at a time.")
            requestedOutputRemaining += count
            // downstream wants output now, resume the read source if necessary
            guard let readSource = self.readSource else {
                fatalError("SocketSource readSource illegally nil during signal.")
            }
            switch readSource.state {
            case .suspended: readSource.resume()
            default: break
            }
        case .cancel: close()
        }
    }

    /// Cancels reading
    public func close() {
        guard let readSource = self.readSource else {
            fatalError("SocketSource readSource illegally nil during signal.")
        }
        readSource.cancel()
        socket.close()
        downstream?.close()
        self.readSource = nil
        downstream = nil
    }

    /// Reads data and outputs to the output stream
    /// important: the socket _must_ be ready to read data
    /// as indicated by a read source.
    private func readData(to downstream: AnyInputStream<UnsafeBufferPointer<UInt8>>) {
        do {
            // prepare the socket if necessary
            guard socket.isPrepared else {
                try socket.prepareSocket()
                // make sure to return, since the socket is no longer "ready"
                return
            }

            let read = try socket.read(into: buffer)
            switch read {
            case .read(let count):
                guard count > 0 else {
                    close()
                    return
                }

                let view = UnsafeBufferPointer<UInt8>(start: buffer.baseAddress, count: count)
                requestedOutputRemaining -= 1
                downstream.next(view)
            case .wouldBlock: fatalError()
            }
        } catch {
            // any errors that occur here cannot be thrown,
            // so send them to stream error catcher.
            downstream.error(error)
        }
    }

    /// Called when the read source signals.
    private func readSourceSignal(isCancelled: Bool) {
        guard !isCancelled else {
            // source is cancelled, we will never receive signals again
            close()
            return
        }

        guard requestedOutputRemaining > 0 else {
            guard let readSource = self.readSource else {
                fatalError("SocketSource readSource illegally nil during signal.")
            }
            // downstream isn't ready for data yet, suspend notifications
            readSource.suspend()
            return
        }

        guard let downstream = self.downstream else {
            // downstream not setup yet
            return
        }

        readData(to: downstream)
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

