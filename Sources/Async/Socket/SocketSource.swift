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
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: Async.InputStream, S.Input == UnsafeBufferPointer<UInt8> {
        /// CALLED ON ACCEPT THREAD
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }

    /// See ConnectionContext.connection
    public func connection(_ event: ConnectionEvent) {
        /// CALLED ON SINK THREAD
        switch event {
        case .request(let count):
            assert(count == 1)
            buffers.releaseReadable()
            requestedOutputRemaining += count
            update()
            resumeReading()
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

        if buffers.canWrite {
            if socketIsEmpty {
                resumeReading()
            } else {
                readData(isCancelled: false)
            }
        }
    }

    /// Cancels reading
    public func close() {
        socket.close()
        downstream?.close()
        if type(of: eventLoop) is DispatchEventLoop.Type {
            resumeReading()
        }
        readSource = nil
        downstream = nil
    }

    /// Resumes reading data.
    private func resumeReading() {
        let source = ensureReadSource()
        switch source.state {
        case .cancelled, .resumed: break
        case .suspended: source.resume()
        }
    }

    /// Suspends reading data.
    private func suspendReading() {
        let source = ensureReadSource()
        switch source.state {
        case .cancelled, .suspended: break
        case .resumed: source.suspend()
        }
    }

    /// Reads data and outputs to the output stream
    /// important: the socket _must_ be ready to read data
    /// as indicated by a read source.
    private func readData(isCancelled: Bool) {
        guard !isCancelled else {
            close()
            return
        }

        guard socket.isPrepared else {
            do {
                try socket.prepareSocket()
            } catch {
                downstream?.error(error)
            }
            return
        }

        // if we were called, socket must no longer be empty
        socketIsEmpty = false

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
                close() // used to be source.cancel
                return
            }

            let view = UnsafeBufferPointer<UInt8>(start: buffer.baseAddress, count: count)
            buffers.addReadable(view)

            if !buffers.canWrite {
                suspendReading()
            }
        case .wouldBlock:
            socketIsEmpty = true
        }

        update()
    }

    /// Returns the existing read source or creates
    /// and stores a new one
    private func ensureReadSource() -> EventSource {
        guard let existing = self.readSource else {
            let readSource = self.eventLoop.onReadable(descriptor: socket.descriptor, readData)
            self.readSource = readSource
            return readSource
        }
        return existing
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

