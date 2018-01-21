import Dispatch
import Foundation

/// An error reading files.
public struct FileError: Error {
    /// See Debuggable.reason
    var reason: String

    /// See Debuggable.identifier
    var identifier: String

    /// Creates a new file reading error.
    init(identifier: String, reason: String) {
        self.reason = reason
        self.identifier = identifier
    }
}

fileprivate final class SingleFile: Async.OutputStream {
    typealias Output = UnsafeBufferPointer<UInt8>

    let path: String
    var closed = false
    var data: Data?

    /// The downstream to stream to
    var downstream: AnyInputStream<Output>?

    init(path: String) {
        self.path = path
    }

    /// See `OutputStream.output`
    func output<S>(to inputStream: S) where S : InputStream, Output == S.Input {
        self.downstream = AnyInputStream(inputStream)
        guard !closed else { return }
        closed = true

        if let data = FileManager.default.contents(atPath: path) {
            self.data = data

            data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
                let buffer = UnsafeBufferPointer<UInt8>(
                    start: pointer,
                    count: data.count
                )

                let promise = Promise(Void.self) // we can ignore this result, since we're never sending another output
                downstream?.next(buffer, promise)
            }
        } else {
            downstream?.error(FileError(identifier: "file-not-found", reason: "The file '\(path)' was not found"))
        }

        downstream?.close()
    }
}

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
        SingleFile(path: path).output(to: stream)
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

