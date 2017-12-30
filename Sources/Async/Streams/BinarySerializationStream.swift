public protocol BinarySerializationStream: Async.Stream, ConnectionContext where Output == UnsafeBufferPointer<UInt8> {
    
}
