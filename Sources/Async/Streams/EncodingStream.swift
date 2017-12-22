/// Capable of encoding futures.
public protocol StreamEncoder: class {
    /// Encodes a future to the encoder.
    func encodeStream<O: OutputStream & ConnectionContext>(_ stream: O) throws where O.Output == Encodable
}

public final class EncodingStream: TransformingStream, ConnectionContext, Encodable {
    public typealias Input = Encodable
    public typealias Output = Encodable
    
    public var upstream: ConnectionContext?
    public var downstream: AnyInputStream<EncodingStream.Output>?
    
    init<S: OutputStream>(_ stream: S) where S.Output == Output {
        stream.output(to: self)
    }
    
    init<S: OutputStream>(_ stream: S) where S.Output: Encodable {
        stream.map(to: Encodable.self) { $0 }.output(to: self)
    }
    
    public func transform(_ input: Input) throws -> Future<Output> {
        return Future(input)
    }
    
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .cancel:
            upstream?.cancel()
        case .request(let amount):
            upstream?.request(count: amount)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        if let encoder = encoder as? StreamEncoder {
            try encoder.encodeStream(self)
        }
    }
}

extension OutputStream where Output == Encodable {
    public func encode() -> EncodingStream {
        return EncodingStream(self)
    }
}

extension OutputStream where Output: Encodable {
    public func encode() -> EncodingStream {
        return EncodingStream(self)
    }
}
