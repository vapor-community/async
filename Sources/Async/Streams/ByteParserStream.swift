/// Parses incoming `ByteBuffer` to an Output. Captures partially complete parsing states.
public protocol ByteParser: TranslatingStream where Input == UnsafeBufferPointer<UInt8> {
    /// Any type that can be used to carry partially completed data into `continueParsing`
    ///
    /// If there are multiple partial states you can use an enum
    associatedtype Partial
    
    /// A state kept by the Async library used to keep track of which data is parsed and if more data is needed
    var state: ByteParserState<Self> { get }
    
    /// Continues parsing a partially parsed Output
    func parseBytes(from buffer: Input, partial: Partial?) throws -> Future<ByteParserResult<Self>>
}

/// Keeps track of variables that are related to the parsing process
public final class ByteParserState<S> where S: ByteParser {
    /// The current offset where is being parsed
    fileprivate var parsedInput: Int
    
    /// Stores partially parsed data
    fileprivate var partiallyParsed: S.Partial?
    
    /// Creates a new state tracker
    public init() {
        parsedInput = 0
    }
}

/// Captures the progress of a parsing step
public enum ByteParserResult<S> where S: ByteParser {
    case uncompleted(S.Partial)
    case completed(consuming: Int, result: S.Output)
}

extension ByteParser {
    /// Parses the inputted byteBuffer to one or no output.
    ///
    /// If output has been achieved, passes it downstream and requests more data otherwise
    ///
    /// When output has been achieved, the remainder of the input buffer will be left unused until more output is requested.
    public func translate(input: UnsafeBufferPointer<UInt8>) throws -> Future<TranslatingStreamResult<Output>> {
        let buffer = UnsafeBufferPointer<UInt8>(
            start: input.baseAddress?.advanced(by: self.state.parsedInput),
            count: input.count - self.state.parsedInput
        )
        
        let state = try parseBytes(from: buffer, partial: self.state.partiallyParsed)

        return state.map(to: TranslatingStreamResult<Output>.self) { state in
            switch state {
            case .uncompleted(let partial):
                self.state.partiallyParsed = partial
                self.state.parsedInput = 0
                return .insufficient
            case .completed(let consumed, let result):
                self.state.parsedInput = self.state.parsedInput &+ consumed
                self.state.partiallyParsed = nil

                if consumed == buffer.count {
                    self.state.parsedInput = 0
                    return .sufficient(result)
                }

                return .excess(result)
            }
        }
    }
}

