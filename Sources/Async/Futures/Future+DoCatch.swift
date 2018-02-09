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
    @discardableResult
    public func `catch`(_ callback: @escaping (Error) -> ()) -> Future<T> {
        addAwaiter { result in
            guard let er = result.error else {
                return
            }

            callback(er)
        }
        
        return self
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

extension Collection where Element : FutureType {
    /// Adds a handler to be asynchronously executed on
    /// completion of all of these futures.
    ///
    /// Will *not* be executed if an error occurrs
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#on-future-completion)
    public func `do`(_ callback: @escaping ([Element.Expectation]) -> ()) -> Future<[Element.Expectation]> {
        return self.flatten().do(callback)
    }
    
    /// Adds a handler to be asynchronously executed on
    /// completion of all of these futures.
    ///
    /// Will *only* be executed if an error occurred in one of these futures.
    /// Successful results will not call this handler.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#on-future-completion)
    @discardableResult
    public func `catch`(_ callback: @escaping (Error) -> ()) -> Future<[Element.Expectation]> {
        return self.flatten().catch(callback)
    }
    
    /// Get called back whenever all of these futures are complete,
    /// ignoring the result.
    @discardableResult
    public func always(_ callback: @escaping () -> ()) -> Future<[Element.Expectation]> {
        return self.flatten().always(callback)
    }
}

