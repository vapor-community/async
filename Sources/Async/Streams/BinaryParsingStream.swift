public protocol BinaryParsingStream: Async.Stream, ConnectionContext where Input == UnsafeBufferPointer<UInt8> {
    associatedtype PartiallyParsed
    
    /// The upstream that is providing byte buffers
    var upstream: ConnectionContext? { get set }
    
    /// The currently parsing buffer
    var upstreamInput: UnsafeBufferPointer<UInt8>? { get set }
    
    /// The current offset where is being parsed
    var parsedInput: Int { get set }
    
    /// The current eventloop, used to dispatch tasks (preventing stack overflows)
    var eventloop: EventLoop { get }
    
    /// Remaining downstream demand
    var downstreamDemand: UInt { get set }
    
    /// Indicates that the stream is currently parsing, preventing multiple actions from being dispatched
    var parsing: Bool { get set }
    
    /// Stores partially parsed data
    var partiallyParsed: PartiallyParsed? { get set }
    
    /// Use a basic output stream to implement server output stream.
    var downstream: AnyInputStream<Output>? { get set }
    
    /// Closes the stream on protocol errors
    var closeOnError: Bool { get }
    
    func continueParsing(_ partial: PartiallyParsed, from buffer: Input) throws -> ParsingState<Output>
    func startParsing(from buffer: Input) throws -> ParsingState<Output>
}

public enum ParsingState<Output> {
    case uncompleted
    case completed(consuming: Int, result: Output)
}

extension BinaryParsingStream {
    /// Must not be called before input
    /// The remaining length after `basePointer`
    public var remainder: Int? {
        guard let count = upstreamInput?.count else {
            return nil
        }
        
        return count - parsedInput
    }
    
    /// The current position where is being parsed
    public var basePointer: UnsafePointer<UInt8>? {
        return upstreamInput?.baseAddress?.advanced(by: parsedInput)
    }
    
    /// The unconsumed data
    public var unconsumedBuffer: UnsafeBufferPointer<UInt8>? {
        guard let remainder = self.remainder, let pointer = self.basePointer else {
            return nil
        }
        
        return UnsafeBufferPointer(start: pointer, count: remainder)
    }
    
    /// Closes the stream on protocol errors by default, which almost every protocol does
    public var closeOnError: Bool {
        return true
    }
    
    public func setInput(to input: Input?) {
        self.upstreamInput = input
        self.parsedInput = 0
    }
    
    public func output<S>(to inputStream: S) where S : Async.InputStream, Output == S.Input {
        self.downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }
    
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            downstream?.close()
        case .connect(let upstream):
            self.upstream = upstream
        case .error(let error):
            downstream?.error(error)
        case .next(let next):
            self.setInput(to: next)
            parseInput()
        }
    }
    
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .cancel:
            self.downstreamDemand = 0
        case .request(let demand):
            self.downstreamDemand += demand
        }
        
        parseInput()
    }
    
    private func parseInput() {
        guard downstreamDemand > 0 else { return }
        
        guard let unconsumedBuffer = unconsumedBuffer else {
            upstream?.request()
            return
        }
        
        //        if eventloop.recursion > eventloop.maxRecursion {
        
        do {
            let state: ParsingState<Output>
            
            if let partiallyParsed = self.partiallyParsed {
                state = try continueParsing(partiallyParsed, from: unconsumedBuffer)
            } else {
                state = try startParsing(from: unconsumedBuffer)
            }
            
            switch state {
            case .uncompleted:
                // All data is drained, we need to provide more data after this
                setInput(to: nil)
                upstream?.request()
            case .completed(let consumed, let result):
                self.parsedInput = self.parsedInput &+ consumed
                
                if parsedInput == upstreamInput?.count {
                    setInput(to: nil)
                }
                
                downstream?.next(result)
                
                if self.upstreamInput == nil {
                    upstream?.request()
                }
            }
        } catch {
            downstream?.error(error)
            
            if closeOnError {
                self.close()
            }
        }
    }
}

