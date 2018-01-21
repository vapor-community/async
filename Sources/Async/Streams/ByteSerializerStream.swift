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
    case awaiting(AnyOutputStream<UnsafeBufferPointer<UInt8>>, state: S.SerializationState?)
}

/// Keeps track of the states for `ByteSerializerStream`
public final class ByteSerializerState<S> where S: ByteSerializer {
    fileprivate struct StreamingState {
        fileprivate var stream: AnyOutputStream<UnsafeBufferPointer<UInt8>>
        fileprivate var buffer: UnsafeBufferPointer<UInt8>?
        fileprivate var completing: Promise<TranslatingStreamResult<S.Output>>
    }
    
    fileprivate var incompleteState: S.SerializationState?
    fileprivate var streaming: StreamingState?
    
    /// Creates a new state machine for `ByteSerializerStream` conformant types
    public init() {}
}

extension ByteSerializer {
    /// Translates the input by serializing it
    public func translate(input context: inout TranslatingStreamInput<Input>) throws -> TranslatingStreamOutput<Output> {
        // This is a struct, so a nil check is required
        if self.state.streaming != nil {
            let promise = Promise<TranslatingStreamResult<Output>>()
            
            self.state.streaming?.completing = promise
            
            return .init(result: promise.future)
        }

        guard let input = context.input else {
            context.close()
            return .insufficient()
        }
        
        let result = try self.serialize(input, state: self.state.incompleteState)
        
        switch result {
        case .complete(let buffer):
            self.state.incompleteState = nil
            
            return .sufficient(buffer)
        case .incomplete(let buffer, let state):
            self.state.incompleteState = state
            
            return .excess(buffer)
        case .awaiting(let stream, let state):
            let promise = Promise<TranslatingStreamResult<Output>>()
            
            self.state.incompleteState = state
            
            stream.drain { buffer in
                self.state.streaming?.completing.complete(.excess(buffer))
            }.catch(onError: promise.fail).finally {
                let completing = self.state.streaming?.completing
                self.state.streaming = nil
                completing?.complete(.insufficient)
            }

            self.state.streaming = ByteSerializerState<Self>.StreamingState(
                stream: stream,
                buffer: nil,
                completing: promise
            )

            return .init(result: promise.future)
        }
    }
}
