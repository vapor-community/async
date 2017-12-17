import Dispatch

enum DispatchSourceState {
    case resumed
    case suspended
    case cancelled
}

/// Data stream wrapper for a dispatch socket.
public final class DispatchSocketStream<Socket, EventLoop>: Stream, ConnectionContext
    where Socket: DispatchSocket, EventLoop: Async.EventLoop
{
    /// See InputStream.Input
    public typealias Input = UnsafeBufferPointer<UInt8>

    /// See OutputStream.Output
    public typealias Output = UnsafeBufferPointer<UInt8>

    /// The client stream's underlying socket.
    public var socket: Socket

    /// Bytes from the socket are read into this buffer.
    /// Views into this buffer supplied to output streams.
    private let outputBuffer: UnsafeMutableBufferPointer<UInt8>

    /// Data being fed into the client stream is stored here.
    private var inputBuffer: UnsafeBufferPointer<UInt8>?

    /// Stores read event source.
    private var readSource: EventLoop.Source?

    /// Stores write event source.
    private var writeSource: EventLoop.Source?

    /// Use a basic stream to easily implement our output stream.
    private var downstream: AnyInputStream<UnsafeBufferPointer<UInt8>>?

    /// The current request controlling incoming write data
    private var upstream: ConnectionContext?

    /// The amount of requested output remaining
    private var requestedOutputRemaining: UInt
    
    /// A strong reference to the current eventloop
    private var eventLoop: EventLoop

    /// The read dispatch source state
    private var readState: DispatchSourceState

    /// The write dispatch source state
    private var writeState: DispatchSourceState

    internal init(socket: Socket, on eventLoop: EventLoop) {
        self.socket = socket
        self.eventLoop = eventLoop
        // Allocate one TCP packet
        let size = 65_507
        self.outputBuffer = UnsafeMutableBufferPointer<UInt8>(start: .allocate(capacity: size), count: size)
        self.inputBuffer = nil
        self.requestedOutputRemaining = 0
        readState = .suspended
        writeState = .suspended
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
            resumeWriting()
        case .connect(let connection):
            upstream = connection
            connection.request()
        case .close:
            /// don't propogate to downstream or we will have an infinite loop
            close()
        case .error(let e):
            /// don't propogate to downstream or we will have an infinite loop
            print("Uncaught Error: \(e)")
            close()
        }
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
            /// We must add checks to this method since it is
            /// called everytime downstream requests more data.
            /// Not checking counts would result in over resuming
            /// the dispatch source.
            let isSuspended = requestedOutputRemaining == 0
            requestedOutputRemaining += count

            /// ensure was suspended and output has actually
            /// been requested
            if isSuspended && requestedOutputRemaining > 0 {
                resumeReading()
            }
        case .cancel: close()
        }
    }

    /// Cancels reading
    public func close() {
        socket.close()
        if EventLoop.self is DispatchEventLoop.Type {
            resumeReading()
            resumeWriting()
        }
        readSource = nil
        writeSource = nil
    }

    /// Resumes reading data.
    private func resumeReading() {
        switch readState {
        case .cancelled, .resumed: break
        case .suspended:
            readState = .resumed
            ensureReadSource().resume()
        }
    }

    /// Suspends reading data.
    private func suspendReading() {
        switch readState {
        case .cancelled, .suspended: break
        case .resumed:
            readState = .suspended
            ensureReadSource().suspend()
        }
    }

    /// Resumes writing data
    private func resumeWriting() {
        switch writeState {
        case .cancelled, .resumed: break
        case .suspended:
            writeState = .resumed
            ensureWriteSource().resume()
        }
    }

    /// Suspends writing data
    private func suspendWriting() {
        switch writeState {
        case .cancelled, .suspended: break
        case .resumed:
            writeState = .suspended
            ensureWriteSource().suspend()
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

        let read: Int
        do {
            read = try socket.read(into: outputBuffer)
        } catch {
            // any errors that occur here cannot be thrown,
            //selfso send them to stream error catcher.
            downstream?.error(error)
            return
        }

        guard read > 0 else {
            close() // used to be source.cancel
            return
        }

        // create a view into our internal buffer and
        // send to the output stream
        let bufferView = UnsafeBufferPointer<UInt8>(
            start: outputBuffer.baseAddress,
            count: read
        )
        downstream?.next(bufferView)

        /// decrement remaining and check if
        /// we need to suspend accepting
        self.requestedOutputRemaining -= 1
        if self.requestedOutputRemaining == 0 {
            suspendReading()
        }
    }

    /// Writes the buffered data to the socket.
    private func writeData(isCancelled: Bool) {
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
            downstream?.error(error)
        }
    }

    /// Returns the existing read source or creates
    /// and stores a new one
    private func ensureReadSource() -> EventLoop.Source {
        guard let existing = self.readSource else {
            let readSource = self.eventLoop.onReadable(descriptor: socket.descriptor, readData)
            self.readSource = readSource
            return readSource
        }
        return existing
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
        outputBuffer.baseAddress.unsafelyUnwrapped.deallocate(capacity: outputBuffer.count)
        outputBuffer.baseAddress.unsafelyUnwrapped.deinitialize()
    }
}

/// MARK: Create

extension DispatchSocket {
    /// Creates a data stream for this socket on the supplied event loop.
    public func stream<EventLoop>(on eventLoop: EventLoop) -> DispatchSocketStream<Self, EventLoop> {
        return DispatchSocketStream(socket: self, on: eventLoop)
    }
}

