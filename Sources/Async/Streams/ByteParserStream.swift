public protocol ByteParserStream: Async.Stream, ConnectionContext where Input == UnsafeBufferPointer<UInt8> {
    /// Any type that can be used to carry partially completed data into `continueParsing`
    ///
    /// If there are multiple partial states you can use an enum
    associatedtype Partial
    
    /// A state kept by the Async library used to keep track of which data is parsed and if more data is needed
    var state: ByteParserStreamState<Self> { get }
    
    /// Closes the stream on protocol errors
    var closeOnError: Bool { get }
    
    /// Continues parsing a partially parsed Output
    func continueParsing(_ partial: Partial, from buffer: Input) throws -> ByteParserResult<Partial, Output>
    
    /// Starts parsing Output, resulting in either a partially or fully completed Output
    func startParsing(from buffer: Input) throws -> ByteParserResult<Partial, Output>
}

public final class ByteParserStreamState<S: ByteParserStream> {
    /// The current eventloop, used to dispatch tasks (preventing stack overflows)
    fileprivate var eventloop: EventLoop
    
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
    
    /// Sends data asynchronously, preventing stack overflows
    fileprivate func send(_ output: S.Output) {
        self.downstream?.next(output)
    }
    
    public init(worker: Worker) {
        eventloop = worker.eventLoop
        parsedInput = 0
        downstreamDemand = 0
        parsing = false
    }
}

public enum ByteParserResult<Partial, Output> {
    case uncompleted(Partial)
    case completed(consuming: Int, result: Output)
}

extension ByteParserStream {
    /// Must not be called before input
    /// The remaining length after `basePointer`
    fileprivate var remainder: Int? {
        guard let count = state.upstreamInput?.count else {
            return nil
        }
        
        return count - state.parsedInput
    }
    
    /// The current position where is being parsed
    fileprivate var basePointer: UnsafePointer<UInt8>? {
        return state.upstreamInput?.baseAddress?.advanced(by: state.parsedInput)
    }
    
    /// The unconsumed data
    fileprivate var unconsumedBuffer: UnsafeBufferPointer<UInt8>? {
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
    
    /// Free implementation of `input`. Do not overwrite in the implementation
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
    
    /// Free implementation of `connection`. Do not overwrite in the implementation
    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .cancel:
            self.state.downstreamDemand = 0
        case .request(let demand):
            self.state.downstreamDemand += demand
        }
        
        parseInput()
    }
    
    /// Parses the inputted byteBuffer to one or no output.
    ///
    /// If output has been achieved, passes it downstream and requests more data otherwise
    ///
    /// When output has been achieved, the remainder of the input buffer will be left unused until more output is requested.
    private func parseInput() {
        guard state.downstreamDemand > 0 else { return }
        
        guard let unconsumedBuffer = unconsumedBuffer else {
            state.upstream?.request()
            return
        }
        
        // TODO: if eventloop.recursion > eventloop.maxRecursion {
        
        do {
            let state: ByteParserResult<Partial, Output>
            
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
                
                self.state.send(result)
                
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

