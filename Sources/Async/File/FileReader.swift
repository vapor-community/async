import Dispatch
import Foundation

/// Capable of reading files asynchronously.
public protocol FileReader {
    /// Reads the file at the supplied path
    /// Supply a queue to complete the future on.
    func read(at path: String, chunkSize: Int) -> AnyOutputStream<UnsafeBufferPointer<UInt8>>

    /// Returns true if the file exists at the supplied path.
    func fileExists(at path: String) -> Bool

    /// Returns true if a directory exists at the supplied path.
    func directoryExists(at path: String) -> Bool
}

extension FileReader {
    /// Reads data at the supplied path and combines into one Data.
    public func read(at path: String, chunkSize: Int) -> Future<Data> {
        let promise = Promise(Data.self)

        var data = Data()
        let stream = self.read(at: path, chunkSize: chunkSize)
        var upstream: ConnectionContext?
        
        stream.drain { _upstream in
            upstream = _upstream
        }.output { buffer in
            let extraData = Data(bytes: buffer.baseAddress!, count: buffer.count)
            data.append(extraData)
            upstream?.request()
        }.catch(onError: promise.fail).finally {
            promise.complete(data)
        }
        
        upstream?.request()
        
        return promise.future
    }
}

public typealias FileOutputStream = AnyOutputStream<UnsafeBufferPointer<UInt8>>
