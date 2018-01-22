public final class PushStream<Pushing>: Stream {
    public typealias Input = Pushing
    public typealias Output = Pushing

    var backlog: [Pushing]
    var downstream: AnyInputStream<Pushing>?
    var isReady: Bool
    var isClosed: Bool

    public init(_ type: Pushing.Type = Pushing.self) {
        backlog = []
        isReady = true
        isClosed = false
    }

    /// Pushes a new `Input` into the stream.
    public func push(_ input: Input) {
        if isReady, let downstream = self.downstream {
            isReady = false
            downstream.next(input).do {
                self.isReady = true
                self.update()
            }.catch { error in
                downstream.error(error)
            }
        } else {
            backlog.insert(input, at: 0)
        }
    }

    /// Checks to see if additional work needs to be done.
    private func update() {
        if let last = self.backlog.popLast() {
            self.push(last)
        } else if isClosed {
            downstream?.close()
        }
    }

    /// See `InputStream.input`
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            isClosed = true
            if backlog.count == 0 {
                downstream?.close()
            }
        case .error(let error):
            downstream?.error(error)
        case .next(let input, let ready):
            self.push(input)
            ready.complete() // input stream can immidately complete since we are backlogging input
        }
    }

    /// See `OutputStream.output`
    public func output<S>(to inputStream: S) where S : InputStream, Output == S.Input {
        downstream = AnyInputStream(inputStream)
        update()
    }
}

