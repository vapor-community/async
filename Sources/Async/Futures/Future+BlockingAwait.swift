import Dispatch

extension Future {
    /// Waits until the specified time for a result.
    ///
    /// Will return the results when available unless the specified
    /// time has been reached, in which case it will timeout
    ///
    /// This is primarily used in unit tests and may cause problems if used in a truely asynchronous environment.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#synchronous-apis)
    public func blockingAwait(deadline time: DispatchTime = .distantFuture) throws -> Expectation {
        let semaphore = DispatchSemaphore(value: 0)
        var awaitedResult: FutureResult<Expectation>?

        addAwaiter { result in
            awaitedResult = result
            semaphore.signal()
        }

        guard semaphore.wait(timeout: time) == .success else {
            throw PromiseTimeout(expecting: Expectation.self)
        }

        return try awaitedResult!.unwrap()
    }

    /// Waits for the specified duration for a result.
    ///
    /// Will return the results when available unless the specified timeout has been reached, in which case it will timeout
    ///
    /// This is primarily used in unit tests and may cause problems if used in a truely asynchronous environment.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#synchronous-apis)
    public func blockingAwait(timeout interval: DispatchTimeInterval) throws -> Expectation {
        return try blockingAwait(deadline: DispatchTime.now() + interval)
    }
}
