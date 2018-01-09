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
    
    /// The current offset where is being parsed
    fileprivate var parsedInput: Int
    
    /// Stores partially parsed data
    fileprivate var partiallyParsed: S.Partial?
    
    public init(worker: Worker) {
        eventloop = worker.eventLoop
        parsedInput = 0
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

