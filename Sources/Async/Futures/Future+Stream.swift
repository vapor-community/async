import Dispatch

extension Future {
    /// Streams the result of this future to the InputStream
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/streams-basics/#chaining-streams_1)
    public func stream<S: InputStream>(to stream: S) where S.Input == Expectation {
        // FIXME
//        self.do(stream.input).catch { error in
//            // stream.report(error)
//        }
    }
}
