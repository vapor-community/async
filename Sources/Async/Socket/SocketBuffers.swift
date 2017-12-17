/// A collection of UnsafeBufferPointer<UInt8>s that can be used to buffer
/// the connection between OS event source and downstream parsers.
internal struct SocketBuffers {
    let writableBuffers: UnsafeMutableBufferPointer<UnsafeMutableBufferPointer<UInt8>>
    let readableBuffers: UnsafeMutableBufferPointer<UnsafeBufferPointer<UInt8>>

    var readableCount: Int
    var readableOffset: Int
    var writableOffset: Int

    var canRead: Bool {
        return readableCount > 0
    }

    var canWrite: Bool {
        return readableCount < writableBuffers.count
    }

    init(count: Int, capacity: Int) {
        writableBuffers = UnsafeMutableBufferPointer<UnsafeMutableBufferPointer<UInt8>>(start: .allocate(capacity: count), count: count)
        readableBuffers = UnsafeMutableBufferPointer<UnsafeBufferPointer<UInt8>>(start: .allocate(capacity: count), count: count)
        for i in 0..<writableBuffers.count {
            writableBuffers[i] = UnsafeMutableBufferPointer<UInt8>(start: .allocate(capacity: capacity), count: capacity)
        }
        readableOffset = 0
        writableOffset = 0
        readableCount = 0
    }

    mutating func leaseReadable() -> UnsafeBufferPointer<UInt8> {
        guard canRead else {
            fatalError()
        }

        defer {
            readableOffset += 1
            if readableOffset >= readableBuffers.count {
                readableOffset = 0
            }
        }
        return readableBuffers[readableOffset]
    }

    mutating func releaseReadable() {
        guard readableCount > 0 else {
            return
        }
        readableCount -= 1
    }

    mutating func nextWritable() -> UnsafeMutableBufferPointer<UInt8> {
        guard canWrite else {
            fatalError()
        }
        return writableBuffers[writableOffset]
    }

    mutating func addReadable(_ buffer: UnsafeBufferPointer<UInt8>) {
        defer {
            writableOffset += 1
            if writableOffset >= writableBuffers.count {
                writableOffset = 0
            }
        }

        readableCount += 1
        readableBuffers[writableOffset] = buffer
    }


    func cleanup() {
        for i in 0..<writableBuffers.count {
            writableBuffers[i].baseAddress?.deallocate(capacity: writableBuffers[i].count)
        }
        writableBuffers.baseAddress?.deallocate(capacity: writableBuffers.count)
        readableBuffers.baseAddress?.deallocate(capacity: readableBuffers.count)
    }
}
