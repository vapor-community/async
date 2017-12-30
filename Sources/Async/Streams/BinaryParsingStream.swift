public protocol BinaryParsingStream: Async.Stream, ConnectionContext where Input == UnsafeBufferPointer<UInt8> {
    associatedtype Partial
    
    /// The current eventloop, used to dispatch tasks (preventing stack overflows)
    var eventloop: EventLoop { get }
    
    var state: BinaryParsingStreamState<Self> { get }
    
    /// Closes the stream on protocol errors
    var closeOnError: Bool { get }
    
    func continueParsing(_ partial: Partial, from buffer: Input) throws -> ParsingState<Partial, Output>
    func startParsing(from buffer: Input) throws -> ParsingState<Partial, Output>
}

public final class BinaryParsingStreamState<S: BinaryParsingStream> {
    /// The upstream that is providing byte buffers
    fileprivate var upstream: ConnectionContext?
    
    /// The currently parsing buffer
    fileprivate var upstreamInput: UnsafeBufferPointer<UInt8>?
    
    /// The current offset where is being parsed
    fileprivate var parsedInput: Int
    
    /// Remaining downstream demand
    fileprivate var downstreamDemand: UInt
    
    /// Indicates that the stream is currently parsing, preventing multiple actions from being dispatched
    fileprivate var parsing: Bool
    
    /// Stores partially parsed data
    fileprivate var partiallyParsed: S.Partial?
    
    /// Use a basic output stream to implement server output stream.
    fileprivate var downstream: AnyInputStream<S.Output>?
    
    public init() {
        parsedInput = 0
        downstreamDemand = 0
        parsing = false
    }
}

public enum ParsingState<Partial, Output> {
    case uncompleted(Partial)
    case completed(consuming: Int, result: Output)
}

extension BinaryParsingStream {
    /// Must not be called before input
    /// The remaining length after `basePointer`
    var remainder: Int? {
        guard let count = state.upstreamInput?.count else {
            return nil
        }
        
        return count - state.parsedInput
    }
    
    /// The current position where is being parsed
    var basePointer: UnsafePointer<UInt8>? {
        return state.upstreamInput?.baseAddress?.advanced(by: state.parsedInput)
    }
    
    /// The unconsumed data
    var unconsumedBuffer: UnsafeBufferPointer<UInt8>? {
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
        self.state.upstreamInput = input
        self.state.parsedInput = 0
    }
    
    public func output<S>(to inputStream: S) where S : Async.InputStream, Output == S.Input {
        self.state.downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }
    
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            state.downstream?.close()
        case .connect(let upstream):
            self.state.upstream = upstream
        case .error(let error):
            state.downstream?.error(error)
        case .next(let next):
            self.setInput(to: next)
            parseInput()
        }
    }
    
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .cancel:
            self.state.downstreamDemand = 0
        case .request(let demand):
            self.state.downstreamDemand += demand
        }
        
        parseInput()
    }
    
    private func parseInput() {
        guard state.downstreamDemand > 0 else { return }
        
        guard let unconsumedBuffer = unconsumedBuffer else {
            state.upstream?.request()
            return
        }
        
        // TODO: if eventloop.recursion > eventloop.maxRecursion {
        
        do {
            let state: ParsingState<Partial, Output>
            
            if let partiallyParsed = self.state.partiallyParsed {
                state = try continueParsing(partiallyParsed, from: unconsumedBuffer)
            } else {
                state = try startParsing(from: unconsumedBuffer)
            }
            
            switch state {
            case .uncompleted:
                // All data is drained, we need to provide more data after this
                setInput(to: nil)
                self.state.upstream?.request()
            case .completed(let consumed, let result):
                self.state.parsedInput = self.state.parsedInput &+ consumed
                
                if self.state.parsedInput == self.state.upstreamInput?.count {
                    setInput(to: nil)
                }
                
                self.state.downstream?.next(result)
                
                if self.state.upstreamInput == nil {
                    self.state.upstream?.request()
                }
            }
        } catch {
            state.downstream?.error(error)
            
            if closeOnError {
                self.close()
            }
        }
    }
}

