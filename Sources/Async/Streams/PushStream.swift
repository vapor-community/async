public final class PushStream<Pushing>: Stream {
    public typealias Input = Pushing
    public typealias Output = Pushing

    var backlog: [Pushing]
    var downstream: AnyInputStream<Pushing>?
    var isReady: Bool
    
    public init(_ type: Pushing.Type = Pushing.self) {
        backlog = []
        isReady = true
    }

    /// Pushes a new `Input` into the stream.
    public func push(_ input: Input) {
        if isReady {
            isReady = false
            downstream!.next(input).do {
                self.isReady = true
                if let last = self.backlog.popLast() {
                    self.push(last)
                }
            }.catch { error in
                self.downstream?.error(error)
            }
        } else {
            backlog.insert(input, at: 0)
        }
    }

    /// See `InputStream.input`
    public func input(_ event: InputEvent<Input>) {
        switch event {
        case .close:
            downstream?.close()
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
    }
}
