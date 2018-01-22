import Dispatch
import Foundation

/// Data stream wrapper for a dispatch socket.
public final class SocketSink<Socket>: InputStream
    where Socket: Async.Socket
{
    /// See InputStream.Input
    public typealias Input = UnsafeBufferPointer<UInt8>

    /// The client stream's underlying socket.
    public var socket: Socket

    /// Data being fed into the client stream is stored here.
    private var inputBuffer: UnsafeBufferPointer<UInt8>?
    
    /// Stores write event source.
    private var writeSource: EventSource?

    /// A strong reference to the current eventloop
    private var eventLoop: EventLoop

    /// True if this sink has been closed
    private var isClosed: Bool

    /// Currently waiting done callback
    private var currentReadyPromise: Promise<Void>?

    /// Creates a new `SocketSink`
    internal init(socket: Socket, on worker: Worker) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        self.inputBuffer = nil
        self.isClosed = false
        let writeSource = self.eventLoop.onWritable(descriptor: socket.descriptor, writeSourceSignal)
        self.writeSource = writeSource
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<UnsafeBufferPointer<UInt8>>) {
        // update variables
        switch event {
        case .next(let input, let ready):
            guard inputBuffer == nil else {
                fatalError("SocketSink upstream is illegally overproducing input buffers.")
            }
            inputBuffer = input
            guard currentReadyPromise == nil else {
                fatalError("SocketSink currentReadyPromise illegally not nil during input.")
            }
            currentReadyPromise = ready
            guard let writeSource = self.writeSource else {
                fatalError("SocketSink writeSource illegally nil during input.")
            }
            // start listening for ready notifications
            writeSource.resume()
        case .close:
            close()
        case .error(let e):
            close()
            fatalError("\(e)")
        }
    }

    /// Cancels reading
    public func close() {
        guard !isClosed else {
            return
        }
        guard let writeSource = self.writeSource else {
            fatalError("SocketSink writeSource illegally nil during close.")
        }
        writeSource.cancel()
        socket.close()
        self.writeSource = nil
        isClosed = true
    }

    /// Writes the buffered data to the socket.
    private func writeData(ready: Promise<Void>) {
        do {
            guard let buffer = self.inputBuffer else {
                fatalError("Unexpected nil SocketSink inputBuffer during writeData")
            }

            let write = try socket.write(from: buffer) // FIXME: add an error handler
            switch write {
            case .wrote(let count):
                switch count {
                case buffer.count:
                    self.inputBuffer = nil
                    ready.complete()
                default:
                    inputBuffer = UnsafeBufferPointer<UInt8>(
                        start: buffer.baseAddress?.advanced(by: count),
                        count: buffer.count - count
                    )
                    writeData(ready: ready)
                }
            case .wouldBlock:
                guard let writeSource = self.writeSource else {
                    fatalError("SocketSink writeSource illegally nil during writeData.")
                }

                // resume for notification when socket is ready again
                writeSource.resume()
                guard currentReadyPromise == nil else {
                    fatalError("SocketSink currentReadyPromise illegally not nil during wouldBlock.")
                }
                currentReadyPromise = ready
            }
        } catch {
            self.error(error)
            ready.complete()
        }
    }

    /// Called when the write source signals.
    private func writeSourceSignal(isCancelled: Bool) {
        guard !isCancelled else {
            // source is cancelled, we will never receive signals again
            close()
            return
        }

        guard let writeSource = self.writeSource else {
            fatalError("SocketSink writeSource illegally nil during signal.")
        }
        // always suspend, we will resume on next wouldBlock
        writeSource.suspend()

        guard let ready = currentReadyPromise else {
            fatalError("SocketSink currentReadyPromise illegaly nil during signal.")
        }
        currentReadyPromise = nil
        writeData(ready: ready)
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func sink(on eventLoop: Worker) -> SocketSink<Self> {
        return .init(socket: self, on: eventLoop)
    }
}
