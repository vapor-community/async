public protocol ProtocolSerializerStream: Async.Stream, ConnectionContext where Output: SerializationResult {
    /// Unrequested backlog to be serialized
    var backlog: [Input] { get set }
    
    var serializing: Input? { get set }
    
    var serializationState: Output.State? { get set }
    
    /// Serialized requests
    var downstreamDemand: UInt { get set }
    
    /// Upstream bytebuffer output stream
    var upstream: ConnectionContext? { get set }
    
    /// Downstream frame input stream
    var downstream: AnyInputStream<Output>? { get set }
    
    /// The current state of parsing
    var state: ProtocolParserState { get set }
    
    /// Transforms the input into output
    ///
    /// Output must call the
    func serialize(_ input: Input, state: Output.State) throws -> Output.State
}

public protocol SerializationResult {
    associatedtype State
}
//
//extension ProtocolSerializerStream {
//    /// InputStream.onInput
//    public func input(_ event: InputEvent<Input>) {
//        // Flush existing data (so the transform function doesn't)
//        flush()
//        
//        switch event {
//        case .close: downstream?.close()
//        case .connect(let upstream):
//            self.upstream = upstream
//        case .error(let error): downstream?.error(error)
//        case .next(let input):
//            state = .ready
//            do {
//                try transform(input)
//            } catch {
//                downstream?.error(error)
//            }
//        }
//        
//        // Flush & request more data if necessary
//        update()
//    }
//    
//    public func connection(_ event: ConnectionEvent) {
//        switch event {
//        case .request(let count):
//            /// downstream has requested output
//            downstreamDemand += count
//        case .cancel:
//            /// FIXME: handle
//            downstreamDemand = 0
//        }
//        
//        update()
//    }
//    
//    /// Flushes parsed values
//    private func flush() {
//        while backlog.count > consumedBacklog, downstreamDemand > 0 {
//            let value = backlog[consumedBacklog]
//            consumedBacklog += 1
//            
//            downstream?.next(value)
//        }
//        
//        backlog.removeFirst(consumedBacklog)
//        consumedBacklog = 0
//    }
//    
//    public func flush(_ value: Output) {
//        flush()
//        
//        if downstreamDemand > 0 {
//            downstream?.next(value)
//            downstreamDemand -= 1
//        } else {
//            self.backlog.append(value)
//        }
//    }
//    
//    /// updates the parser's state
//    public func update() {
//        // Flush existing data, if any
//        flush()
//        
//        /// if demand is 0, we don't want to do anything
//        guard downstreamDemand > 0 else {
//            return
//        }
//        
//        switch state {
//        case .awaitingUpstream:
//            /// we are waiting for upstream, nothing to be done
//            break
//        case .ready:
//            /// ask upstream for some data
//            state = .awaitingUpstream
//            upstream?.request()
//        }
//    }
//    
//    public func output<S>(to inputStream: S) where S: Async.InputStream, Output == S.Input {
//        downstream = AnyInputStream(inputStream)
//        inputStream.connect(to: self)
//    }
//}
//
//extension UnsafeBufferPointer: SerializationResult {
//    public typealias State = Int
//}

