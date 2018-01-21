import Dispatch
import Foundation

/// Capable of reading files asynchronously.
public protocol FileReader {
    /// Reads the file at the supplied path
    /// Supply a queue to complete the future on.
    func read<S>(at path: String, into stream: S, chunkSize: Int)
    where S: Async.InputStream, S.Input == UnsafeBufferPointer<UInt8>

    /// Returns true if the file exists at the supplied path.
    func fileExists(at path: String) -> Bool

    /// Returns true if a directory exists at the supplied path.
    func directoryExists(at path: String) -> Bool
}

//extension FileReader {
//    /// Reads data at the supplied path and combines into one Data.
//    public func read(at path: String, chunkSize: Int) -> Future<Data> {
//        let promise = Promise(Data.self)
//
//        var data = Data()
//        
//        let stream = DrainStream(UnsafeBufferPointer<UInt8>.self, onInput: { buffer, upstream in
//            let extraData = Data(bytes: buffer.baseAddress!, count: buffer.count)
//            data.append(extraData)
//            upstream.request()
//        }, onError: promise.fail, onClose: {
//            promise.complete(data)
//        })
//        
//        self.read(at: path, into: stream, chunkSize: chunkSize)
//        stream.upstream!.request()
//        
//        return promise.future
//    }
//}

public typealias FileOutputStream = AnyOutputStream<UnsafeBufferPointer<UInt8>>
