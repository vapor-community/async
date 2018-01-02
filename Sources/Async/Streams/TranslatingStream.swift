public protocol TranslatingStream {
    associatedtype Input
    associatedtype Output
    func translate(input: Input) -> TranslatingStreamResult<Output>
}

extension TranslatingStream {
    public func stream(on worker: Worker) -> TranslatingStreamWrapper<Self> {
        return .init(translator: self, on: worker)
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
    private var eventLoop: EventLoop
    private var updateCount: Int

    init(translator: Translator, on worker: Worker) {
        self.translator = translator
        self.eventLoop = worker.eventLoop
        demand = 0
        updateCount = 0
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
            if updateCount > 64 {
                eventLoop.async {
                    self.demand += count
                    self.updateCount = 0
                    self.update()
                }
            } else {
                demand += count
                updateCount += 1
                update()
            }
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
            demand -= 1
            downstream?.next(output)
        case .excess(let output):
            demand -= 1
            downstream?.next(output)
        }
        update()
    }
}

public enum TranslatingStreamResult<Output> {
    case insufficient
    case sufficient(Output)
    case excess(Output)
}

fileprivate enum ChunkingStreamState<S> {
    case ready
    case insufficient(S)
    case excess(S)
}

public final class ArrayChunkingStream<T>: TranslatingStream {
    private var state: ChunkingStreamState<[T]>
    public let size: Int

    public init(size: Int) {
        state = .ready
        self.size = size
    }

    public func translate(input: [T]) -> TranslatingStreamResult<[T]> {
        switch state {
        case .ready:
            return handle(input)
        case .insufficient(let remainder):
            let input = remainder + input
            return handle(input)
        case .excess(let input):
            return handle(input)
        }
    }

    private func handle(_ input: [T]) -> TranslatingStreamResult<[T]> {
        if input.count == size {
            state = .ready
            return .sufficient(input)
        } else if input.count > size {
            let output = [T](input[..<size])
            let remainder = [T](input[size...])
            state = .excess(remainder)
            return .excess(output)
        } else {
            state = .insufficient(input)
            return .insufficient
        }
    }
}
