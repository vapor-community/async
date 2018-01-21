import Dispatch

extension Future {
    /// Streams the result of this future to the InputStream
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-basics/#chaining-streams_1)
    public func stream<S: InputStream>(to stream: S) -> Future<Void> where S.Input == Expectation {
        let promise = Promise(Void.self)
        self.do { result in
            stream.onInput(result).chain(to: promise)
        }.catch { error in
            stream.onError(error)
        }
        return promise.future
    }
}
