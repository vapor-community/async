public protocol ByteParserStream: TranslatingStream where Input == UnsafeBufferPointer<UInt8> {
    /// Any type that can be used to carry partially completed data into `continueParsing`
    ///
    /// If there are multiple partial states you can use an enum
    associatedtype Partial
    
    /// A state kept by the Async library used to keep track of which data is parsed and if more data is needed
    var state: ByteParserStreamState<Self> { get }
    
    /// Continues parsing a partially parsed Output
    func parseBytes(from buffer: Input, partial: Partial?) throws -> ByteParserResult<Self>
}

public final class ByteParserStreamState<S> where S: ByteParserStream {
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

public enum ByteParserResult<S> where S: ByteParserStream {
    case uncompleted(S.Partial)
    case completed(consuming: Int, result: S.Output)
}

extension ByteParserStream {
    /// Parses the inputted byteBuffer to one or no output.
    ///
    /// If output has been achieved, passes it downstream and requests more data otherwise
    ///
    /// When output has been achieved, the remainder of the input buffer will be left unused until more output is requested.
    public func translate(input: UnsafeBufferPointer<UInt8>) throws -> TranslatingStreamResult<Output> {
        self.state.parsedInput = 0
        
        let state = try parseBytes(from: input, partial: self.state.partiallyParsed)
        
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

