public protocol TranslatingStream: Stream, ConnectionContext {
    var upstream: ConnectionContext? { get set }
    var downstream: AnyInputStream<Output>? { get set }
    var input: Input? { get set }
    var demand: UInt { get set }
    func translate(input: Input) -> TranslatingStreamResult<Output>
}

public enum TranslatingStreamResult<Output> {
    case insufficient
    case sufficient(Output)
    case excess(Output)
}

extension TranslatingStream {
    public func update() {
        guard demand > 0 else {
            return
        }

        guard let input = self.input else {
            upstream?.request()
            return
        }

        switch translate(input: input) {
        case .insufficient:
            self.input = nil
        case .sufficient(let output):
            self.input = nil
            downstream?.next(output)
            demand -= 1
        case .excess(let output):
            downstream?.next(output)
            demand -= 1
        }

        update()
    }

    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            downstream?.close()
            downstream = nil
            upstream = nil
        case .connect(let upstream):
            self.upstream = upstream
        case .error(let error):
            downstream?.error(error)
        case .next(let next):
            self.input = next
            update()
        }
    }

    public func connection(_ event: ConnectionEvent) {
        switch event {
        case .cancel:
            upstream?.cancel()
            upstream = nil
            downstream = nil
        case .request(let count):
            demand += count
            update()
        }
    }

    public func output<S>(to inputStream: S) where S: InputStream, Output == S.Input {
        downstream = AnyInputStream(inputStream)
        inputStream.connect(to: self)
    }
}

public enum WordParsingStreamState {
    case partial(String)
    case excess([String])
}

public final class WordParsingStream: TranslatingStream {
    public typealias Input = String
    public typealias Output = String

    public var upstream: ConnectionContext?
    public var downstream: AnyInputStream<String>?
    public var demand: UInt
    public var input: String?
    
    public var state: WordParsingStreamState

    public init() {
        state = .partial("")
        demand = 0
    }

    public func translate(input: String) -> TranslatingStreamResult<String> {
        print("\(state): \(input)")

        switch state {
        case .excess(var words):
            let next = words.removeFirst()
            switch words.count {
            case 0:
                state = .partial("")
                return .sufficient(next)
            default:
                state = .excess(words)
                return .excess(next)
            }
        case .partial(let partial):
            if input.contains(" ") {
                var words = input.split(separator: " ").map(String.init)
                switch words.count {
                case 0: fatalError()
                case 1:
                    state = .partial("")
                    return .sufficient(partial + input)
                default:
                    let next = words.removeFirst()
                    state = .excess(words)
                    return .excess(partial + next)
                }
            } else {
                state = .partial(partial + input)
                return .insufficient
            }
        }
    }
}
