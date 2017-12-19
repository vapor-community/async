import Dispatch
import Foundation

public final class File: FileReader, FileCache {
    /// Cached data.
    private var cache: [Int: Data]

    /// This file's queue. Must be sync.
    /// all calls to this File reader must be made
    /// from this queue.
    let eventLoop: EventLoop

    private var source: EventSource?

    /// Create a new CFile
    /// FIXME: add cache maximum
    public init(on worker: Worker) {
        self.cache = [:]
        self.eventLoop = worker.eventLoop
    }

    /// See FileReader.read
    public func read<S>(at path: String, into stream: S, chunkSize: Int)
        where S: Async.InputStream, S.Input == UnsafeBufferPointer<UInt8>
    {
        eventLoop.async {
            if let data = FileManager.default.contents(atPath: path) {
                let buffer = UnsafeBufferPointer<UInt8>(
                    start: data.withUnsafeBytes { $0 },
                    count: data.count
                )
                stream.next(buffer)
            } else {
                fatalError("File not found at: \(path)")
            }
            stream.close()
        }
    }

    /// See FileReader.fileExists
    public func fileExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return false
        }
        return !isDirectory.boolValue
    }

    /// See FileReader.directoryExists
    public func directoryExists(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            return false
        }
        return isDirectory.boolValue
    }

    /// See FileCache.getFile
    public func getCachedFile(at path: String) -> Data? {
        return cache[path.hashValue]
    }

    /// See FileCache.setFile
    public func setCachedFile(file: Data?, at path: String) {
        cache[path.hashValue] = file
    }
}

#if os(Linux)
    extension Bool {
        fileprivate var boolValue: Bool { return self }
    }
#endif
