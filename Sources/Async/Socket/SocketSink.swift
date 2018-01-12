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

    /// True if the socket has returned that it would block
    /// on the previous call
    private var socketIsFull: Bool

    internal init(socket: Socket, on worker: Worker) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        // Allocate one TCP packet
        self.inputBuffer = nil
        self.socketIsFull = false
        self.written = 0
        let writeSource = self.eventLoop.onWritable(descriptor: socket.descriptor, writeSourceSignal)
        writeSource.resume()
        self.writeSource = writeSource
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<UnsafeBufferPointer<UInt8>>) {
        switch event {
        case .next(let input):
            /// crash if the upstream is illegally overproducing data
            guard inputBuffer == nil else {
                fatalError("\(#function) was called while inputBuffer is not nil")
            }

            inputBuffer = input
            update()
        case .connect(let connection):
            upstream = connection
            if !socketIsFull {
                update()
            }
        case .close:
            close()
        case .error(let e):
            print("Uncaught Error: \(e)")
            close()
        }
    }

    /// Cancels reading
    public func close() {
        socket.close()
        writeSource = nil
        upstream = nil
    }

    private func update() {
        guard inputBuffer != nil else {
            upstream?.request()
            return
        }
        writeData()
    }

    /// Writes the buffered data to the socket.
    private func writeData() {
        // ensure socket is prepared
        guard socket.isPrepared else {
            do {
                try socket.prepareSocket()
            } catch {
                /// FIXME: handle better
                print(error)
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
                case input.count:
                    // wrote everything, suspend until we get more data to write
                    inputBuffer = nil
                    upstream?.request()
                default:
                    written += count
                }
            case .wouldBlock:
                socketIsFull = true
            }
        } catch {
            /// FIXME: handle better
            print("Uncaught Error: \(error)")
        }
    }

    /// Called when the write source signals.
    private func writeSourceSignal(isCancelled: Bool) {
        guard !isCancelled else {
            close()
            return
        }
        socketIsFull = false
        update()
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func sink(on eventLoop: Worker) -> SocketSink<Self> {
        return .init(socket: self, on: eventLoop)
    }
}
