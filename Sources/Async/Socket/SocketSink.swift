import Dispatch
import Foundation

/// Data stream wrapper for a dispatch socket.
public final class SocketSink<Socket, EventLoop>: InputStream
    where Socket: Async.Socket, EventLoop: Async.EventLoop
{
    /// See InputStream.Input
    public typealias Input = UnsafeBufferPointer<UInt8>

    /// The client stream's underlying socket.
    public var socket: Socket

    /// Data being fed into the client stream is stored here.
    private var inputBuffer: ByteBuffer?

    /// Stores write event source.
    private var writeSource: EventLoop.Source?

    /// The current request controlling incoming write data
    private var upstream: ConnectionContext?

    /// A strong reference to the current eventloop
    private var eventLoop: EventLoop

    internal init(socket: Socket, on eventLoop: EventLoop) {
        self.socket = socket
        self.eventLoop = eventLoop
        // Allocate one TCP packet
        self.inputBuffer = nil
    }

    /// See InputStream.input
    public func input(_ event: InputEvent<ByteBuffer>) {
        switch event {
        case .next(let input):
            /// crash if the upstream is illegally overproducing data
            guard inputBuffer == nil else {
                fatalError("\(#function) was called while inputBuffer is not nil")
            }

            inputBuffer = input
            resumeWriting()
        case .connect(let connection):
            /// CALLED ON ACCEPT THREAD
            upstream = connection
            resumeWriting()
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
        if EventLoop.self is DispatchEventLoop.Type {
            resumeWriting()
        }
        writeSource = nil
        upstream = nil
    }

    /// Resumes writing data
    private func resumeWriting() {
        let source = ensureWriteSource()
        switch source.state {
        case .cancelled, .resumed: break
        case .suspended: source.resume()
        }
    }

    /// Suspends writing data
    private func suspendWriting() {
        let source = ensureWriteSource()
        switch source.state {
        case .cancelled, .suspended: break
        case .resumed: source.suspend()
        }
    }

    /// Writes the buffered data to the socket.
    private func writeData(isCancelled: Bool) {
        guard !isCancelled else {
            close()
            return
        }

        guard inputBuffer != nil else {
            upstream?.request()
            suspendWriting()
            return
        }


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
            let count = try socket.write(from: input)
            switch count {
            case input.count:
                // wrote everything, suspend until we get more data to write
                inputBuffer = nil
                suspendWriting()
                upstream?.request()
            default: print("not all data was written: \(count)/\(input.count)")
            }
        } catch {
            /// FIXME: handle better
            print(error)
        }
    }

    /// Creates a new WriteSource if there is no write source yet
    private func ensureWriteSource() -> EventLoop.Source {
        guard let existing = self.writeSource else {
            let writeSource = self.eventLoop.onWritable(descriptor: socket.descriptor, writeData)
            self.writeSource = writeSource
            return writeSource
        }
        return existing
    }

    /// Deallocated the pointer buffer
    deinit {
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func sink<EventLoop>(on eventLoop: EventLoop) -> SocketSink<Self, EventLoop> {
        return .init(socket: self, on: eventLoop)
    }
}


