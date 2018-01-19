extension Future {
    /// Adds a handler to be asynchronously executed on
    /// completion of this future.
    ///
    /// Will *not* be executed if an error occurrs
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#on-future-completion)
    public func `do`(_ callback: @escaping (Expectation) -> ()) -> Future<T> {
        addAwaiter { result in
            guard let ex = result.expectation else {
                return
            }

            callback(ex)
        }

        return self
    }

    /// Adds a handler to be asynchronously executed on
    /// completion of this future.
    ///
    /// Will *only* be executed if an error occurred.
    //// Successful results will not call this handler.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#on-future-completion)
    public func `catch`(_ callback: @escaping (Error) -> ()) {
        addAwaiter { result in
            guard let er = result.error else {
                return
            }

            callback(er)
        }
    }

    /// Get called back whenever the future is complete,
    /// ignoring the result.
    @discardableResult
    public func always(_ callback: @escaping () -> ()) -> Future<T> {
        addAwaiter { _ in
            callback()
        }

        return self
    }
}
