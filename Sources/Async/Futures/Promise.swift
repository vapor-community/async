/// A promise is a variable that can be completed when it's ready
///
/// It can be transformed into a future which can only be read
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#creating-a-promise)
public final class Promise<T> {
    /// Contains information about callbacks
    /// waiting for this future to complete
    struct Awaiter {
        let callback: Future<T>.ResultCallback
    }
    
    /// This promise's future.
    public var future: Future<T> {
        return Future<T>(referring: self)
    }
    
    var result: FutureResult<T>?
    
    /// A list of all handlers waiting to
    var awaiters: [Awaiter]
    
    var isCompleted: Bool {
        return result != nil
    }

    /// Create a new promise.
    public init(_ expectation: T.Type = T.self) {
        self.awaiters = []
    }

    /// Fail to fulfill the promise.
    /// If the promise has already been fulfilled,
    /// it will quiety ignore the input.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#creating-a-promise)
    public func fail(_ error: Error) {
        complete(with: .error(error))
    }

    /// Fulfills the promise.
    /// If the promise has already been fulfilled,
    /// it will quiety ignore the input.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#creating-a-promise)
    public func complete(_ expectation: T) {
        complete(with: .expectation(expectation))
    }
    
    /// Completes the result, notifying awaiters.
    fileprivate func complete(with result: FutureResult<T>) {
        guard self.result == nil else {
            return
        }
        self.result = result
        
        for awaiter in awaiters {
            awaiter.callback(result)
        }
        
        // release the awaiters to prevent retain cycles
        awaiters = []
    }
}

extension Promise where T == Void {
    /// Complete a void promise.
    public func complete() {
        complete(())
    }
}
