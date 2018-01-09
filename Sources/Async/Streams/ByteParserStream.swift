public protocol ByteParserStream: TranslatingStream where Input == UnsafeBufferPointer<UInt8> {
    /// Any type that can be used to carry partially completed data into `continueParsing`
    ///
    /// If there are multiple partial states you can use an enum
    associatedtype Partial
    
    /// A state kept by the Async library used to keep track of which data is parsed and if more data is needed
    var state: ByteParserStreamState<Self> { get }
    
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
    /// Parses the inputted byteBuffer to one or no output.
    ///
    /// If output has been achieved, passes it downstream and requests more data otherwise
    ///
    /// When output has been achieved, the remainder of the input buffer will be left unused until more output is requested.
    public func translate(input: UnsafeBufferPointer<UInt8>) throws -> TranslatingStreamResult<Output> {
        self.state.parsedInput = 0
        
        let state: ByteParserResult<Partial, Output>
        
        if let partiallyParsed = self.state.partiallyParsed {
            state = try continueParsing(partiallyParsed, from: input)
        } else {
            state = try startParsing(from: input)
        }
        
        switch state {
        case .uncompleted:
            // All data is drained, we need to provide more data after this
            self.state.upstream?.request()
            
            return .insufficient
        case .completed(let consumed, let result):
            self.state.parsedInput = self.state.parsedInput &+ consumed
            
            if self.state.parsedInput == input.count {
                self.state.parsedInput = 0
                return .sufficient(result)
            }
            
            return .excess(result)
        }
    }
}

