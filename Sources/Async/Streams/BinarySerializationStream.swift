public protocol BinarySerializationStream: Async.Stream, ConnectionContext where Output == UnsafeBufferPointer<UInt8> {
    var downstream: AnyInputStream<Output>? { get set }
    var serializing: Input? { get set }
}
