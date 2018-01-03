public protocol ByteSerializerStream: Async.Stream, ConnectionContext where Output == UnsafeBufferPointer<UInt8> {
    associatedtype SerializationState
    
    /// A serialization state that is used to keep track of unwritten `backlog` that has been inputted but couldn't yet be processed reactively.
    var state: ByteSerializerStreamState<Self> { get }
    
    /// Serializes the input to a ByteBuffer. The buffer *must* be available asynchronously.
    ///
    /// The output buffer must not be deallocated or overwritten until either a new input is being serialized or the Serializer is deallocated.
    ///
    /// The state provided is defined in the associated `SerializationState` and can be used to track incomplete write states
    ///
    /// Returns either a completely or incompletelyserialized state.
    func serialize(_ input: Input, state: SerializationState?) -> ByteSerializerStreamResult<Self>
}

public enum ByteSerializerStreamResult<S: ByteSerializerStream> {
    case incomplete(UnsafeBufferPointer<UInt8>, state: S.SerializationState)
    case complete(UnsafeBufferPointer<UInt8>)
}

/// Keeps track of the states for `ByteSerializerStream`
public final class ByteSerializerStreamState<S: ByteSerializerStream> {
    /// The downstream to send output bytes to
    fileprivate var downstream: AnyInputStream<UnsafeBufferPointer<UInt8>>?
    
    /// The upstream that is providing unserialized data
    fileprivate var upstream: ConnectionContext?
    
    /// Remaining downstream demand
    fileprivate var downstreamDemand: UInt
    
    /// Keeps track of the `backlog`'s consumed data so it can be drained and cleaned up efficiently
    fileprivate var consumedBacklog: Int
    
    /// The backlog of `Input` to serialize
    fileprivate var backlog: [S.Input]
    
    fileprivate var incompleteState: (S.Input, S.SerializationState)?
    
    /// Unsets all values, cleaning up the state
    fileprivate func cancel() {
        // clean up
        backlog = []
        downstreamDemand = 0
        
        // disconnect
        downstream = nil
        upstream = nil
    }
    
    /// Cleans up the backlog
    fileprivate func cleanUpBacklog() {
        if consumedBacklog > 0 {
            backlog.removeFirst(consumedBacklog)
            consumedBacklog = 0
        }
    }
    
    /// Sends the buffer to downstream
    fileprivate func send(_ buffer: UnsafeBufferPointer<UInt8>) {
        downstream?.next(buffer)
    }
    
    fileprivate var needMoreInput: Bool {
        return backlog.count > consumedBacklog || incompleteState != nil
    }
    
    /// Creates a new state machine for `ByteSerializerStream` conformant types
    public init() {
        downstreamDemand = 0
        backlog = []
        consumedBacklog = 0
    }
}

extension ByteSerializerStream {
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .request(let amount):
            state.downstreamDemand += amount
            
            defer {
                state.cleanUpBacklog()
            }
            
            // Serialized remainder backlog
            while state.downstreamDemand > 0, state.needMoreInput {
                // Decrement in advance to prevent bugs with recursive requesting
                state.downstreamDemand -= 1
                
                let input: Input
                let serializationState: SerializationState?
                
                if let incompleteState = state.incompleteState {
                    input = incompleteState.0
                    serializationState = incompleteState.1
                } else {
                    // Serialize the current backlog position
                    input = state.backlog[state.consumedBacklog]
                    serializationState = nil
                    
                    // Increment before sending, to prevent recursion bugs
                    state.consumedBacklog += 1
                }
                
                _serialize(input, state: serializationState)
            }
        case .cancel:
            state.cancel()
        }
    }
    
    fileprivate func _serialize(_ input: Input, state: SerializationState?) {
        let result = self.serialize(input, state: state)
        
        // send downstream
        switch result {
        case .incomplete(let buffer, let serializationState):
            self.state.incompleteState = (input, serializationState)
            self.state.send(buffer)
        case .complete(let buffer):
            self.state.send(buffer)
        }
    }
    
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .connect(let context):
            state.upstream = context
        case .close:
            state.cancel()
        case .error(let error):
            state.downstream?.error(error)
        case .next(let input):
            self.queue(input)
        }
    }
    
    public func output<S>(to inputStream: S) where S : InputStream, Self.Output == S.Input {
        state.downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }
    
    fileprivate func queue(_ input: Input) {
        guard state.downstreamDemand > 0 else {
            state.backlog.append(input)
            return
        }
        
        let serializing: Input
        
        defer {
            // Clean up the backlog buffer
            state.cleanUpBacklog()
        }
        
        if state.backlog.count > state.consumedBacklog {
            // Append first, so the `next` doesn't trigger reading more data
            state.backlog.append(input)
            
            serializing = state.backlog[state.consumedBacklog]
        } else {
            // Serialize without appending, saving performance
            serializing = input
        }
        
        // Serialize and send downstream
        _serialize(serializing, state: nil)
    }
}
