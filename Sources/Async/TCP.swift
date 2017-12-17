// MARK: TEMP

public typealias Byte = UInt8
public typealias Bytes = [Byte]
public typealias ByteBuffer = UnsafeBufferPointer<Byte>
public typealias MutableByteBuffer = UnsafeMutableBufferPointer<Byte>
public typealias BytesPointer = UnsafePointer<Byte>
public typealias MutableBytesPointer = UnsafeMutablePointer<Byte>

// MARK: TCP
import Dispatch
import Darwin
import Foundation

/// Any TCP socket. It doesn't specify being a server or client yet.
public struct TCPSocket: Socket {
    /// The file descriptor related to this socket
    public let descriptor: Int32

    /// The remote's address
    public var address: TCPAddress?

    /// True if the socket is non blocking
    public let isNonBlocking: Bool

    /// True if the socket should re-use addresses
    public let shouldReuseAddress: Bool

    /// Creates a TCP socket around an existing descriptor
    public init(
        established: Int32,
        isNonBlocking: Bool,
        shouldReuseAddress: Bool,
        address: TCPAddress?
    ) {
        self.descriptor = established
        self.isNonBlocking = isNonBlocking
        self.shouldReuseAddress = shouldReuseAddress
        self.address = address
    }

    /// Creates a new TCP socket
    public init(
        isNonBlocking: Bool = true,
        shouldReuseAddress: Bool = true
    ) throws {
        let sockfd = socket(AF_INET, SOCK_STREAM, 0)
        guard sockfd > 0 else {
            throw TCPError.posix(errno, identifier: "socketCreate")
        }

        if isNonBlocking {
            // Set the socket to async/non blocking I/O
            guard fcntl(sockfd, F_SETFL, O_NONBLOCK) == 0 else {
                throw TCPError.posix(errno, identifier: "setNonBlocking")
            }
        }

        if shouldReuseAddress {
            var yes = 1
            let intSize = socklen_t(MemoryLayout<Int>.size)
            guard setsockopt(sockfd, SOL_SOCKET, SO_REUSEPORT, &yes, intSize) == 0 else {
                throw TCPError.posix(errno, identifier: "setReuseAddress")
            }
        }

        if shouldReuseAddress {
            var yes = 1
            let intSize = socklen_t(MemoryLayout<Int>.size)
            guard setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, intSize) == 0 else {
                throw TCPError.posix(errno, identifier: "setReuseAddress")
            }
        }

        self.init(
            established: sockfd,
            isNonBlocking: isNonBlocking,
            shouldReuseAddress: shouldReuseAddress,
            address: nil
        )
    }

    /// Disables broken pipe from signaling this process.
    /// Broken pipe is common on the internet and if uncaught
    /// it will kill the process.
    public func disablePipeSignal() {
        signal(SIGPIPE, SIG_IGN)

        #if !os(Linux)
            var n = 1
            setsockopt(self.descriptor, SOL_SOCKET, SO_NOSIGPIPE, &n, numericCast(MemoryLayout<Int>.size))
        #endif

        // TODO: setsockopt(self.descriptor, SOL_TCP, TCP_NODELAY, &n, numericCast(MemoryLayout<Int>.size)) ?
    }

    /// Read data from the socket into the supplied buffer.
    /// Returns the amount of bytes actually read.
    public func read(into buffer: MutableByteBuffer) throws -> Int {
        let receivedBytes = Darwin.read(descriptor, buffer.baseAddress!, buffer.count)
        guard receivedBytes != -1 else {
            switch errno {
            case EINTR:
                // try again
                return try read(into: buffer)
            case ECONNRESET:
                // closed by peer, need to close this side.
                // Since this is not an error, no need to throw unless the close
                // itself throws an error.
                _ = close()
                return 0
            case EAGAIN:
                // timeout reached (linux)
                return 0
            default:
                throw TCPError.posix(errno, identifier: "read")
            }
        }

        guard receivedBytes > 0 else {
            // receiving 0 indicates a proper close .. no error.
            // attempt a close, no failure possible because throw indicates already closed
            // if already closed, no issue.
            // do NOT propogate as error
            _ = close()
            return 0
        }

        return receivedBytes
    }

    /// Writes all data from the pointer's position with the length specified to this socket.
    public func write(from buffer: ByteBuffer) throws -> Int {
        guard let pointer = buffer.baseAddress else {
            return 0
        }

        let sent = send(descriptor, pointer, buffer.count, 0)
        guard sent != -1 else {
            switch errno {
            case EINTR:
                // try again
                return try write(from: buffer)
            case ECONNRESET, EBADF:
                // closed by peer, need to close this side.
                // Since this is not an error, no need to throw unless the close
                // itself throws an error.
                self.close()
                return 0
            default:
                throw TCPError.posix(errno, identifier: "write")
            }
        }

        return sent
    }

    /// Closes the socket
    public func close() {
        Darwin.close(descriptor)
    }
}

/// Accepts client connections to a socket.
///
/// Uses Async.OutputStream API to deliver accepted clients
/// with back pressure support. If overwhelmed, input streams
/// can cause the TCP server to suspend accepting new connections.
///
/// [Learn More →](https://docs.vapor.codes/3.0/sockets/tcp-server/)
public struct TCPServer {
    /// A closure that can dictate if a client will be accepted
    ///
    /// `true` for accepted, `false` for not accepted
    public typealias WillAccept = (TCPClient) -> (Bool)

    /// Controls whether or not to accept a client
    ///
    /// Useful for security purposes
    public var willAccept: WillAccept?

    /// This server's TCP socket.
    public let socket: TCPSocket

    /// Creates a TCPServer from an existing TCPSocket.
    public init(socket: TCPSocket) throws {
        self.socket = socket
    }

    /// Starts listening for peers asynchronously
    public func start(hostname: String = "0.0.0.0", port: UInt16, backlog: Int32 = 128) throws {
        /// bind the socket and start listening
        try socket.bind(hostname: hostname, port: port)
        try socket.listen(backlog: backlog)
    }

    /// Accepts a client and outputs to the output stream
    /// important: the socket _must_ be ready to accept a client
    /// as indicated by a read source.
    public mutating func accept() throws -> TCPClient? {
        let accepted = try socket.accept()

        /// init a tcp client with the socket and assign it an event loop
        let client = try TCPClient(socket: accepted)

        /// check the will accept closure to approve this connection
        if let shouldAccept = willAccept, !shouldAccept(client) {
            client.close()
            return nil
        }

        /// output the client
        return client
    }

    /// Stops the server
    public func stop() {
        socket.close()
    }
}

extension TCPSocket {
    /// bind - bind a name to a socket
    /// http://man7.org/linux/man-pages/man2/bind.2.html
    fileprivate func bind(hostname: String = "0.0.0.0", port: UInt16) throws {
        var hints = addrinfo()

        // Support both IPv4 and IPv6
        hints.ai_family = AF_INET

        // Specify that this is a TCP Stream
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        // If the AI_PASSIVE flag is specified in hints.ai_flags, and node is
        // NULL, then the returned socket addresses will be suitable for
        // bind(2)ing a socket that will accept(2) connections.
        hints.ai_flags = AI_PASSIVE


        // Look ip the sockeaddr for the hostname
        var result: UnsafeMutablePointer<addrinfo>?

        var res = getaddrinfo(hostname, port.description, &hints, &result)
        guard res == 0 else {
            throw TCPError.posix(
                errno,
                identifier: "getAddressInfo",
                possibleCauses: [
                    "The address that binding was attempted on does not refer to your machine."
                ],
                suggestedFixes: [
                    "Bind to `0.0.0.0` or to your machine's IP address"
                ]
            )
        }
        defer {
            freeaddrinfo(result)
        }

        guard let info = result else {
            throw TCPError(identifier: "unwrapAddress", reason: "Could not unwrap address info.")
        }

        res = Darwin.bind(descriptor, info.pointee.ai_addr, info.pointee.ai_addrlen)
        guard res == 0 else {
            throw TCPError.posix(errno, identifier: "bind")
        }
    }

    /// listen - listen for connections on a socket
    /// http://man7.org/linux/man-pages/man2/listen.2.html
    fileprivate func listen(backlog: Int32 = 4096) throws {
        let res = Darwin.listen(descriptor, backlog)
        guard res == 0 else {
            throw TCPError.posix(errno, identifier: "listen")
        }
    }

    /// accept, accept4 - accept a connection on a socket
    /// http://man7.org/linux/man-pages/man2/accept.2.html
    fileprivate func accept() throws -> TCPSocket {
        let (clientfd, address) = try TCPAddress.withSockaddrPointer { address -> Int32 in
            var size = socklen_t(MemoryLayout<sockaddr>.size)

            let descriptor = Darwin.accept(self.descriptor, address, &size)

            guard descriptor > 0 else {
                throw TCPError.posix(errno, identifier: "accept")
            }

            return descriptor
        }

        let socket = TCPSocket(
            established: clientfd,
            isNonBlocking: isNonBlocking,
            shouldReuseAddress: shouldReuseAddress,
            address: address
        )

        return socket
    }
}

/// Read and write byte buffers from a TCPClient.
///
/// These are usually created as output by a TCPServer.
///
/// [Learn More →](https://docs.vapor.codes/3.0/sockets/tcp-client/)
public final class TCPClient {
    /// The client stream's underlying socket.
    public var socket: TCPSocket

    /// Handles close events
    public typealias WillClose = () -> ()

    /// Will be triggered before closing the socket, as part of the cleanup process
    public var willClose: WillClose?

    /// Creates a new TCPClient from an existing TCPSocket.
    public init(socket: TCPSocket) throws {
        self.socket = socket
        self.socket.disablePipeSignal()
    }

    /// Attempts to connect to a server on the provided hostname and port
    public func connect(hostname: String, port: UInt16) throws  {
        try self.socket.connect(hostname: hostname, port: port)
    }

    /// Returns a boolean describing if the socket is still healthy and open
    public var isConnected: Bool {
        var error = 0
        getsockopt(socket.descriptor, SOL_SOCKET, SO_ERROR, &error, nil)
        return error == 0
    }

    /// Stops the client
    public func close() {
        willClose?()
        socket.close()
    }
}

extension TCPSocket {
    /// connect - initiate a connection on a socket
    /// http://man7.org/linux/man-pages/man2/connect.2.html
    fileprivate mutating func connect(hostname: String, port: UInt16) throws {
        var hints = addrinfo()

        // Support both IPv4 and IPv6
        hints.ai_family = AF_INET

        // Specify that this is a TCP Stream
        hints.ai_socktype = SOCK_STREAM

        // Look ip the sockeaddr for the hostname
        var result: UnsafeMutablePointer<addrinfo>?

        var res = getaddrinfo(hostname, port.description, &hints, &result)
        guard res == 0 else {
            throw TCPError.posix(
                errno,
                identifier: "getAddressInfo",
                possibleCauses: [
                    "The address supplied could not be resolved."
                ]
            )
        }
        defer {
            freeaddrinfo(result)
        }

        guard let info = result else {
            throw TCPError(identifier: "unwrapAddress", reason: "Could not unwrap address info.")
        }

        res = Darwin.connect(descriptor, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if res != 0 {
            switch errno {
            case EINTR:
                // the connection will now be made async regardless of socket type
                // http://www.madore.org/~david/computers/connect-intr.html
                if !isNonBlocking {
                    print("EINTR on a blocking socket")
                }
            case EINPROGRESS:
                if !isNonBlocking {
                    fatalError("EINPROGRESS on a blocking socket")
                }
            default: throw TCPError.posix(errno, identifier: "connect")
            }
        }

        self.address = TCPAddress(storage: info.pointee.ai_addr.pointee)
    }
}

/// A socket address
public struct TCPAddress {
    /// The raw underlying storage
    let storage: sockaddr_storage

    /// Creates a new socket address
    init(storage: sockaddr_storage) {
        self.storage = storage
    }

    /// Creates a new socket address
    init(storage: sockaddr) {
        var storage = storage

        self.storage = withUnsafePointer(to: &storage) { pointer in
            return pointer.withMemoryRebound(to: sockaddr_storage.self, capacity: 1) { storage in
                return storage.pointee
            }
        }
    }

    static func withSockaddrPointer<T>(
        do closure: ((UnsafeMutablePointer<sockaddr>) throws -> (T))
        ) rethrows -> (T, TCPAddress) {
        var addressStorage = sockaddr_storage()

        let other = try withUnsafeMutablePointer(to: &addressStorage) { pointer in
            return try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                return try closure(socketAddress)
            }
        }

        let address = TCPAddress(storage: addressStorage)

        return (other, address)
    }
}

extension TCPAddress: Equatable {
    /// Compares 2 addresses to be equal
    public static func ==(lhs: TCPAddress, rhs: TCPAddress) -> Bool {
        let lhs = lhs.storage
        let rhs = rhs.storage

        // They must have the same family
        guard lhs.ss_family == rhs.ss_family else {
            return false
        }

        switch numericCast(lhs.ss_family) as UInt32 {
        case numericCast(AF_INET):
            // If the family is IPv4, compare the 2 as IPv4
            return lhs.withIn_addr { lhs in
                return rhs.withIn_addr { rhs in
                    return memcmp(&lhs, &rhs, MemoryLayout<in6_addr>.size) == 0
                }
            }
        case numericCast(AF_INET6):
            // If the family is IPv6, compare the 2 as IPv6
            return lhs.withIn6_addr { lhs in
                return rhs.withIn6_addr { rhs in
                    return memcmp(&lhs, &rhs, MemoryLayout<in6_addr>.size) == 0
                }
            }
        default:
            // Impossible scenario
            fatalError()
        }
    }

}

extension TCPAddress {
    /// The remote peer's connection's port
    public var port: UInt16 {
        var copy = self.storage

        let val: UInt16

        switch numericCast(self.storage.ss_family) as UInt32 {
        case numericCast(AF_INET):
            // Extract the port from the struct cast as sockaddr_in
            val = withUnsafePointer(to: &copy) { pointer -> UInt16 in
                pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer -> UInt16 in
                    return pointer.pointee.sin_port
                }
            }
        case numericCast(AF_INET6):
            // Extract the port from the struct cast as sockaddr_in6
            val = withUnsafePointer(to: &copy) { pointer -> UInt16 in
                pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer -> UInt16 in
                    return pointer.pointee.sin6_port
                }
            }
        default:
            // Impossible scenario
            fatalError()
        }

        return htons(val)
    }

    /// The remote's IP address
    public var remoteAddress: String {
        let stringData: UnsafeMutablePointer<Int8>
        let maxStringLength: socklen_t

        switch numericCast(self.storage.ss_family) as UInt32 {
        case numericCast(AF_INET):
            // Extract the remote IPv4 address
            maxStringLength = socklen_t(INET_ADDRSTRLEN)

            // Allocate an IPv4 address
            stringData = UnsafeMutablePointer<Int8>.allocate(capacity: numericCast(maxStringLength))

            _ = self.storage.withIn_addr { address in
                inet_ntop(numericCast(self.storage.ss_family), &address, stringData, maxStringLength)
            }
        case numericCast(AF_INET6):
            // Extract the remote IPv6 address

            // Allocate an IPv6 address
            maxStringLength = socklen_t(INET6_ADDRSTRLEN)
            stringData = UnsafeMutablePointer<Int8>.allocate(capacity: numericCast(maxStringLength))

            _ = self.storage.withIn6_addr { address in
                inet_ntop(numericCast(self.storage.ss_family), &address, stringData, maxStringLength)
            }
        default:
            // Impossible scenario
            fatalError()
        }

        defer {
            // Clean up
            stringData.deallocate(capacity: numericCast(maxStringLength))
        }

        // This cannot fail
        return String(validatingUTF8: stringData)!
    }
}

extension sockaddr_storage {
    // Accesses the sockaddr_storage as sockaddr_in
    fileprivate func withIn_addr<T>(call: ((inout in_addr)->(T))) -> T {
        var copy = self

        return withUnsafePointer(to: &copy) { pointer in
            return pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                var address = pointer.pointee.sin_addr

                return call(&address)
            }
        }
    }

    // Accesses the sockaddr_storage as sockaddr_in6
    fileprivate func withIn6_addr<T>(call: ((inout in6_addr)->(T))) -> T {
        var copy = self

        return withUnsafePointer(to: &copy) { pointer in
            return pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                var address = pointer.pointee.sin6_addr

                return call(&address)
            }
        }
    }
}

/// converts host byte order to network byte order
fileprivate func htons(_ value: UInt16) -> UInt16 {
    return (value << 8) &+ (value >> 8)
}

/// Errors that can be thrown while working with TCP sockets.
public struct TCPError:Swift.Error {
    public static let readableName = "TCP Error"
    public let identifier: String
    public var reason: String
    public var file: String
    public var function: String
    public var line: UInt
    public var column: UInt
    public var stackTrace: [String]
    public var possibleCauses: [String]
    public var suggestedFixes: [String]

    /// Create a new TCP error.
    public init(
        identifier: String,
        reason: String,
        possibleCauses: [String] = [],
        suggestedFixes: [String] = [],
        file: String = #file,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        self.identifier = identifier
        self.reason = reason
        self.file = file
        self.function = function
        self.line = line
        self.column = column
        self.stackTrace = []
        self.possibleCauses = possibleCauses
        self.suggestedFixes = suggestedFixes
    }

    /// Create a new TCP error from a POSIX errno.
    static func posix(
        _ errno: Int32,
        identifier: String,
        possibleCauses: [String] = [],
        suggestedFixes: [String] = [],
        file: String = #file,
        function: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) -> TCPError {
        let message = Darwin.strerror(errno)
        let string = String(cString: message!, encoding: .utf8) ?? "unknown"
        return TCPError(
            identifier: identifier,
            reason: string,
            possibleCauses: possibleCauses,
            suggestedFixes: suggestedFixes,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }
}

/// Stream representation of a TCP server.
public final class TCPClientStream<EventLoop>: OutputStream, ConnectionContext
    where EventLoop: Async.EventLoop
{
    /// See OutputStream.Output
    public typealias Output = TCPClient

    /// The server being streamed
    public var server: TCPServer

    /// This stream's event loop
    public let eventLoop: EventLoop

    /// Downstream client and eventloop input stream
    private var downstream: AnyInputStream<Output>?

    /// The amount of requested output remaining
    private var requestedOutputRemaining: UInt

    /// Keep a reference to the read source so it doesn't deallocate
    private var acceptSource: EventLoop.Source?

    /// Use TCPServer.stream to create
    internal init(server: TCPServer, on eventLoop: EventLoop) {
        self.eventLoop = eventLoop
        self.server = server
        self.requestedOutputRemaining = 0
    }

    /// See OutputStream.output
    public func output<S>(to inputStream: S) where S: InputStream, S.Input == Output {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }

    /// See ConnectionContext.connection
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case.request(let count):
            /// handle downstream requesting data
            /// suspend will be called automatically if the
            /// remaining requested output count ever
            /// reaches zero.
            /// the downstream is expected to continue
            /// requesting additional output as it is ready.
            /// the server will automatically resume if
            /// additional clients are requested after
            /// suspend has been called
            self.request(count)
        case .cancel:
            /// handle downstream canceling output requests
            self.cancel()
        }
    }

    /// Resumes accepting clients if currently suspended
    /// and count is greater than 0
    private func request(_ accepting: UInt) {
        let isSuspended = requestedOutputRemaining == 0
        if accepting == .max {
            requestedOutputRemaining = .max
        } else {
            requestedOutputRemaining += accepting
        }

        if isSuspended && requestedOutputRemaining > 0 {
            ensureAcceptSource().resume()
        }
    }

    /// Cancels the stream
    private func cancel() {
        server.stop()
        downstream?.close()
        if requestedOutputRemaining == 0 {
            /// dispatch sources must be resumed before
            /// deinitializing
            acceptSource?.resume()
        }
        acceptSource = nil
    }

    /// Accepts a client and outputs to the stream
    private func accept(isCancelled: Bool) {
        do {
            guard let client = try server.accept() else {
                // the client was rejected
                return
            }

            //            let eventLoop = eventLoopsIterator.next()

            downstream?.next(client)

            /// decrement remaining and check if
            /// we need to suspend accepting
            if requestedOutputRemaining != .max {
                requestedOutputRemaining -= 1
                if requestedOutputRemaining == 0 {
                    ensureAcceptSource().suspend()
                    requestedOutputRemaining = 0
                }
            }
        } catch {
            downstream?.error(error)
        }
    }

    /// Returns the existing accept source or creates
    /// and stores a new one
    private func ensureAcceptSource() -> EventLoop.Source {
        guard let existing = acceptSource else {
            /// create a new accept source
            let source = self.eventLoop.onReadable(descriptor: server.socket.descriptor, accept)
            acceptSource = source
            return source
        }

        /// return the existing source
        return existing
    }
}

extension TCPServer {
    /// Create a stream for this TCP server.
    /// - parameter on: the event loop to accept clients on
    /// - parameter assigning: the event loops to assign to incoming clients
    public func stream<EventLoop>(on eventLoop: EventLoop) -> TCPClientStream<EventLoop> {
        return .init(server: self, on: eventLoop)
    }
}
