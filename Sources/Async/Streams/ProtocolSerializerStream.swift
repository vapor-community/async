public protocol ProtocolSerializerStream: Async.Stream, ConnectionContext {
    /// Unrequested backlog to be serialized
    var backlog: [Input] { get set }
    
    var consumedBacklog: Int { get set }
    
    var serializing: Input? { get set }
    
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
    func serialize(_ input: Input) throws
}

extension ProtocolSerializerStream {
    /// InputStream.onInput
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close: downstream?.close()
        case .connect(let upstream):
            self.upstream = upstream
        case .error(let error): downstream?.error(error)
        case .next(let input):
            state = .ready
            flushBacklog(and: input)
        }
        
        // Flush & request more data if necessary
        update()
    }
    
    private func flushBacklog(and input: Input? = nil) {
        defer {
            backlog.removeFirst(consumedBacklog)
        }
        
        func canSerialize() -> Bool {
            if downstreamDemand == 0 {
                if let input = input {
                    backlog.append(input)
                }
                
                return false
            }
            
            return true
        }
        
        do {
            // Finish serializing currently serilializing entity
            if let serializing = serializing {
                guard canSerialize() else { return }
                
                try self.serialize(serializing)
            }
            
            // Catch up with backlog
            for entity in backlog[consumedBacklog...] {
                guard canSerialize() else { return }
                
                try serialize(entity)
                consumedBacklog += 1
            }
            
            // Flush new entry
            guard let input = input else {
                return
            }
            
            guard canSerialize() else { return }
            
            try serialize(input)
        } catch {
            downstream?.error(error)
        }
    }
    
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .request(let count):
            /// downstream has requested output
            downstreamDemand += count
            
            flushBacklog()
        case .cancel:
            /// FIXME: handle
            downstreamDemand = 0
        }
        
        update()
    }
    
    public func flush(_ value: Output) {
        guard downstreamDemand > 0 else {
            fatalError("Incorrect serialization implementation. Don't call the `serialize` function manually")
        }
        
        downstream?.next(value)
        downstreamDemand -= 1
    }
    
    /// updates the parser's state
    public func update() {
        flushBacklog()
        
        /// if demand is 0, we don't want to do anything
        guard downstreamDemand > 0 else {
            return
        }
        
        switch state {
        case .awaitingUpstream:
            /// we are waiting for upstream, nothing to be done
            break
        case .ready:
            /// ask upstream for some data
            state = .awaitingUpstream
            upstream?.request()
        }
    }
    
    public func output<S>(to inputStream: S) where S: Async.InputStream, Output == S.Input {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }
}
