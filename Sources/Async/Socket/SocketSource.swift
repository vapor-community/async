import Dispatch
import Foundation

/// Data stream wrapper for a dispatch socket.
public final class SocketSource<Socket>: OutputStream
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
    
    /// A strong reference to the current eventloop
    private var eventLoop: EventLoop

    /// True if this source has been closed
    private var isClosed: Bool

    /// Creates a new `SocketSource`
    internal init(socket: Socket, on worker: Worker, bufferSize: Int) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        self.isClosed = false
        self.buffer = .init(start: .allocate(capacity: bufferSize), count: bufferSize)
        let readSource = self.eventLoop.onReadable(descriptor: socket.descriptor, readSourceSignal)
        self.readSource = readSource
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: Async.InputStream, S.Input == UnsafeBufferPointer<UInt8> {
        downstream = AnyInputStream(inputStream)
        guard let readSource = self.readSource else {
            fatalError("SocketSource readSource illegally nil during output.")
        }
        readSource.resume()
    }

    /// Cancels reading
    public func close() {
        guard !isClosed else {
            return
        }
        guard let readSource = self.readSource else {
            fatalError("SocketSource readSource illegally nil during close.")
        }
        readSource.cancel()
        socket.close()
        downstream?.close()
        self.readSource = nil
        downstream = nil
        isClosed = true
    }

    /// Reads data and outputs to the output stream
    /// important: the socket _must_ be ready to read data
    /// as indicated by a read source.
    private func readData() {
        guard let downstream = self.downstream else {
            fatalError("Unexpected nil downstream on SocketSource during readData.")
        }
        do {
            let read = try socket.read(into: buffer)
            switch read {
            case .read(let count):
                guard count > 0 else {
                    close()
                    return
                }

                let view = UnsafeBufferPointer<UInt8>(start: buffer.baseAddress, count: count)
                downstream.next(view) {
                    guard let readSource = self.readSource else {
                        fatalError("SocketSource readSource illegally nil on readData.")
                    }
                    readSource.resume()
                }
            case .wouldBlock:
                guard let readSource = self.readSource else {
                    fatalError("SocketSource readSource illegally nil on wouldBlock.")
                }
                readSource.resume()
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

        guard let readSource = self.readSource else {
            fatalError("SocketSource readSource illegally nil during signal.")
        }
        // always suspend, we will resume on wouldBlock
        readSource.suspend()
        readData()
    }

    /// Deallocated the pointer buffer
    deinit {
        buffer.baseAddress!.deinitialize()
        buffer.baseAddress!.deallocate(capacity: buffer.count)
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func source(on eventLoop: Worker, bufferSize: Int = 4096) -> SocketSource<Self> {
        return .init(socket: self, on: eventLoop, bufferSize: bufferSize)
    }
}

