public protocol TranslatingStream {
    associatedtype Input
    associatedtype Output
    func translate(input: Input) -> TranslatingStreamResult<Output>
}

extension TranslatingStream {
    public func stream() -> TranslatingStreamWrapper<Self> {
        return .init(translator: self)
    }
}

public final class TranslatingStreamWrapper<Translator>: Stream, ConnectionContext
    where Translator: TranslatingStream
{
    public typealias Input = Translator.Input
    public typealias Output = Translator.Output

    private var upstream: ConnectionContext?
    private var downstream: AnyInputStream<Output>?
    private var input: Input?
    private var demand: UInt
    private var translator: Translator

    init(translator: Translator) {
        self.translator = translator
        demand = 0
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

    private func update() {
        guard demand > 0 else {
            return
        }

        guard let input = self.input else {
            upstream?.request()
            return
        }

        switch translator.translate(input: input) {
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
}

public enum TranslatingStreamResult<Output> {
    case insufficient
    case sufficient(Output)
    case excess(Output)
}

public enum WordParsingStreamState {
    case partial(String)
    case excess([String])
}

public final class WordParsingStream: TranslatingStream {
    public var state: WordParsingStreamState

    public init() {
        state = .partial("")
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
