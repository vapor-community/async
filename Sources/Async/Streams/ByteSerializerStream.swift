/// Serializes input into one or more `ByteBuffer`s
///
/// Requires the sent ByteBuffer to be available asynchronously.
public protocol ByteSerializer: TranslatingStream where Output == UnsafeBufferPointer<UInt8> {
    associatedtype SerializationState
    
    /// A serialization state that is used to keep track of unwritten `backlog` that has been inputted but couldn't yet be processed reactively.
    var state: ByteSerializerState<Self> { get }
    
    /// Serializes the input to a ByteBuffer. The buffer *must* be available asynchronously.
    ///
    /// The output buffer must not be deallocated or overwritten until either a new input is being serialized or the Serializer is deallocated.
    ///
    /// The state provided is defined in the associated `SerializationState` and can be used to track incomplete write states
    ///
    /// Returns either a completely or incompletelyserialized state.
    func serialize(_ input: Input, state: SerializationState?) throws -> ByteSerializerResult<Self>
}

/// Indicates the progress in serializing the S.Input
public enum ByteSerializerResult<S> where S: ByteSerializer {
    case incomplete(UnsafeBufferPointer<UInt8>, state: S.SerializationState)
    case complete(UnsafeBufferPointer<UInt8>)
}

/// Keeps track of the states for `ByteSerializerStream`
public final class ByteSerializerState<S> where S: ByteSerializer {
    fileprivate var incompleteState: S.SerializationState?
    
    /// Creates a new state machine for `ByteSerializerStream` conformant types
    public init() {}
}

extension ByteSerializer {
    /// Translates the input by serializing it
    public func translate(input: Input) throws -> TranslatingStreamResult<Output> {
        let result = try self.serialize(input, state: self.state.incompleteState)
        
        switch result {
        case .complete(let buffer):
            self.state.incompleteState = nil
            
            return .sufficient(buffer)
        case .incomplete(let buffer, let state):
            self.state.incompleteState = state
            
            return .excess(buffer)
        }
    }
}
