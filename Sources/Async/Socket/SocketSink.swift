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
    private var inputBuffer: UnsafeBufferPointer<UInt8>? {
        didSet {
            written = 0
        }
    }
    
    /// The amount of bytes already written from the `inputBuffer`
    private var written: Int
    
    /// Stores write event source.
    private var writeSource: EventSource?

    /// The current request controlling incoming write data
    private var upstream: ConnectionContext?

    /// A strong reference to the current eventloop
    private var eventLoop: EventLoop

    /// True if we are waiting on upstream
    private var isAwaitingUpstream: Bool

    internal init(socket: Socket, on worker: Worker) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        self.inputBuffer = nil
        self.written = 0
        self.isAwaitingUpstream = false
        let writeSource = self.eventLoop.onWritable(descriptor: socket.descriptor, writeSourceSignal)
        writeSource.resume()
        self.writeSource = writeSource
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<UnsafeBufferPointer<UInt8>>) {
        switch event {
        case .next(let input):
            isAwaitingUpstream = false

            /// crash if the upstream is illegally overproducing data
            guard inputBuffer == nil else {
                fatalError("\(#function) was called while inputBuffer is not nil")
            }

            inputBuffer = input
        case .connect(let connection):
            upstream = connection
        case .close:
            close()
        case .error(let e):
            close()
            fatalError("\(e)")
        }
    }

    /// Cancels reading
    public func close() {
        socket.close()
        writeSource = nil
        upstream = nil
    }

    /// Writes the buffered data to the socket.
    private func writeData() {
        // ensure socket is prepared
        guard socket.isPrepared else {
            do {
                try socket.prepareSocket()
            } catch {
                fatalError("\(error)")
            }
            return
        }

        guard let input = inputBuffer else {
            fatalError("\(#function) called while inputBuffer is nil")
        }

        do {
            let buffer = UnsafeBufferPointer<UInt8>(
                start: input.baseAddress?.advanced(by: written),
                count: input.count - written
            )
            
            let write = try socket.write(from: buffer)
            switch write {
            case .wrote(let count):
                switch count + written {
                case input.count: inputBuffer = nil
                default: written += count
                }
            case .wouldBlock: fatalError()
            }
        } catch {
            fatalError("\(error)")
        }
    }

    /// Called when the write source signals.
    private func writeSourceSignal(isCancelled: Bool) {
        guard !isCancelled else {
            close()
            return
        }

        guard inputBuffer != nil else {
            if !isAwaitingUpstream {
                if let upstream = self.upstream {
                    upstream.request()
                } else {
                    // no upstream ready yet
                }
            }
            return
        }

        writeData()
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func sink(on eventLoop: Worker) -> SocketSink<Self> {
        return .init(socket: self, on: eventLoop)
    }
}
