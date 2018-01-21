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

    private var awaitingSignal: (() -> ())?

    /// Creates a new `SocketSink`
    internal init(socket: Socket, on worker: Worker) {
        self.socket = socket
        self.eventLoop = worker.eventLoop
        self.inputBuffer = nil
        // self.isAwaitingUpstream = false
        self.isClosed = false
        let writeSource = self.eventLoop.onWritable(descriptor: socket.descriptor, writeSourceSignal)
//        writeSource.resume()
        self.writeSource = writeSource
    }

    /// See InputStream.input
    public func onInput(_ next: UnsafeBufferPointer<UInt8>) -> Future<Void> {
        // update variables
        guard inputBuffer == nil else {
            fatalError("SocketSink upstream is illegally overproducing input buffers.")
        }
        inputBuffer = next
        return writeData()
    }

    public func onError(_ error: Error) {
        close()
        fatalError("\(error)")
    }

    public func onClose() {
        close()
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
    private func writeData() -> Future<Void> {
        return Future<Void>.flatMap {
            let promise = Promise(Void.self)
            guard let buffer = self.inputBuffer else {
                fatalError("Unexpected `nil` SocketSink inputBuffer on during writeData.")
            }

            let write = try self.socket.write(from: buffer)
            switch write {
            case .wrote(let count):
                switch count {
                case buffer.count:
                    self.inputBuffer = nil
                    promise.complete()
                default:
                    self.inputBuffer = UnsafeBufferPointer<UInt8>(
                        start: buffer.baseAddress?.advanced(by: count),
                        count: buffer.count - count
                    )
                    self.writeData().chain(to: promise)
                }
            case .wouldBlock:
                guard let writeSource = self.writeSource else {
                    fatalError("SocketSink writeSource illegally nil during writeData.")
                }
                writeSource.resume()
                self.awaitingSignal = {
                    self.writeData().chain(to: promise)
                }
            }

            return promise.future
        }
    }

    /// Called when the write source signals.
    private func writeSourceSignal(isCancelled: Bool) {
        guard !isCancelled else {
            // source is cancelled, we will never receive signals again
            close()
            return
        }

        // we should have a write source if just signaled
        guard let writeSource = self.writeSource else {
            fatalError("SocketSink writeSource illegally nil during signal.")
        }

        // always suspend on signal, we will resume on wouldBlock
        writeSource.suspend()

        // call the waiting code
        let awaiting = awaitingSignal!
        awaitingSignal = nil
        awaiting()
    }
}

/// MARK: Create

extension Socket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func sink(on eventLoop: Worker) -> SocketSink<Self> {
        return .init(socket: self, on: eventLoop)
    }
}
