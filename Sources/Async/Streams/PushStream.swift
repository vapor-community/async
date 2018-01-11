public final class PushStream<Pushing>: Stream, ConnectionContext {
    public typealias Input = Pushing
    public typealias Output = Pushing
    
    var downstreamDemand: UInt
    var consumedBacklog: Int
    var backlog: [Pushing]
    var upstream: ConnectionContext?
    var downstream: AnyInputStream<Pushing>?
    
    public init() {
        backlog = []
        consumedBacklog = 0
        downstreamDemand = 0
    }
    
    /// Pushes remaining backlog until the downstream demand is 0
    ///
    /// Removes pushed backlog afterwards
    func cleanUpBacklog() {
        // Defers to prevent removing more than once if called recursively
        defer {
            backlog.removeFirst(consumedBacklog)
            consumedBacklog = 0
        }
        
        // Serialized remainder backlog
        while downstreamDemand > 0, consumedBacklog < self.backlog.count {
            let pushed = backlog[consumedBacklog]
            consumedBacklog += 1
            push(pushed)
        }
    }
    
    /// Pushes an entity to downstream
    fileprivate func push(_ entity: Pushing) {
        assert(downstreamDemand > 0)
        
        // Decrement in advance to prevent bugs with recursive requesting
        downstreamDemand -= 1
        
        downstream?.next(entity)
    }
    
    /// See `ConnectionContext.connection`
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .request(let amount):
            downstreamDemand += amount
            
            cleanUpBacklog()
        case .cancel:
            self.downstreamDemand = 0
        }
    }
    
    /// See `InputStream.input`
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .connect(let context):
            self.upstream = context
        case .close:
            downstream?.close()
        case .error(let error):
            downstream?.error(error)
        case .next(let input):
            self.queue(input)
        }
    }
    
    /// See `OutputStream.output`
    public func output<S>(to inputStream: S) where S : InputStream, Output == S.Input {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }
    
    /// Queues a new input to the backlog and serializes the first input efficiently
    fileprivate func queue(_ input: Input) {
        guard downstreamDemand > 0 else {
            backlog.append(input)
            return
        }
        
        if backlog.count > consumedBacklog {
            // Append first, so the `next` doesn't trigger reading more data
            backlog.append(input)
        } else {
            push(input)
        }
        
        // Clean up the backlog buffer
        cleanUpBacklog()
    }
}
