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

    /// The current request controlling incoming write data
    private var upstream: ConnectionContext?

    /// A strong reference to the current eventloop
    private var eventLoop: EventLoop

    /// True if we are waiting on upstream
    private var isAwaitingUpstream: Bool

    /// Creates a new `SocketSink`
    internal init(socket: Socket, on worker: Worker) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        self.inputBuffer = nil
        self.isAwaitingUpstream = false
        let writeSource = self.eventLoop.onWritable(
            descriptor: socket.descriptor,
            // config: .init(trigger: .level),
            writeSourceSignal
        )
        writeSource.resume()
        self.writeSource = writeSource
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<UnsafeBufferPointer<UInt8>>) {
        // update variables
        switch event {
        case .next(let input):
            isAwaitingUpstream = false
            assert(inputBuffer == nil, "SocketSink upstream is illegally overproducing input buffers.")
            inputBuffer = input
        case .connect(let connection):
            upstream = connection
        case .close:
            close()
        case .error(let e):
            close()
            fatalError("\(e)")
        }

        // resume write source if necessary
        switch event {
        case .next, .connect:
            guard let writeSource = self.writeSource else {
                fatalError("SocketSink writeSource illegally nil during incoming input.")
            }
            switch writeSource.state {
            case .suspended: writeSource.resume()
            default: break
            }
        default: break
        }
    }

    /// Cancels reading
    public func close() {
        guard let writeSource = self.writeSource else {
            fatalError("SocketSink writeSource illegally nil during close.")
        }
        writeSource.cancel()
        socket.close()
        self.writeSource = nil
        upstream = nil
    }

    /// Writes the buffered data to the socket.
    private func writeData(buffer: UnsafeBufferPointer<UInt8>) {
        // ensure socket is prepared
        guard socket.isPrepared else {
            do {
                try socket.prepareSocket()
            } catch {
                fatalError("\(error)")
            }
            return
        }

        let write = try! socket.write(from: buffer) // FIXME: add an error handler
        switch write {
        case .wrote(let count):
            switch count {
            case buffer.count: self.inputBuffer = nil
            default:
                inputBuffer = UnsafeBufferPointer<UInt8>(
                    start: buffer.baseAddress?.advanced(by: count),
                    count: buffer.count - count
                )
            }
        case .wouldBlock: fatalError("SocketSink write illegally returned wouldBlock")
        }
    }

    /// Called when the write source signals.
    private func writeSourceSignal(isCancelled: Bool) {
        guard !isCancelled else {
            // source is cancelled, we will never receive signals again
            close()
            return
        }

        // ensure there's an input buffer to write
        guard let buffer = inputBuffer else {
            if let upstream = self.upstream, !isAwaitingUpstream {
                // there's no input buffer, and we aren't already waiting upstream
                // request the next buffer
                isAwaitingUpstream = true
                upstream.request()
            } else {
                guard let writeSource = self.writeSource else {
                    fatalError("SocketSink writeSource illegally nil during signal.")
                }
                // we are waiting on upstream (connect or next data), suspend notifications
                writeSource.suspend()
            }
            return
        }

        writeData(buffer: buffer)
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func sink(on eventLoop: Worker) -> SocketSink<Self> {
        return .init(socket: self, on: eventLoop)
    }
}
