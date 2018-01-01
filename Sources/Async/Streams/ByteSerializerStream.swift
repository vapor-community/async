public protocol ByteSerializerStream: Async.Stream, ConnectionContext where Output == UnsafeBufferPointer<UInt8> {
    var state: ByteSerializerStreamState<Self> { get }
    
    func serialize(_ input: Input) -> UnsafeBufferPointer<UInt8>
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
            while state.downstreamDemand > 0, state.backlog.count > state.consumedBacklog {
                // Decrement in advance to prevent bugs with recursive requesting
                state.downstreamDemand -= 1
                
                // Serialize the current backlog position
                let buffer = self.serialize(state.backlog[state.consumedBacklog])
                
                // Increment before sending, to prevent recursion bugs
                state.consumedBacklog += 1
                
                // send downstream
                state.send(buffer)
            }
        case .cancel:
            state.cancel()
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
    
    private func queue(_ input: Input) {
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
        state.send(self.serialize(serializing))
    }
}
