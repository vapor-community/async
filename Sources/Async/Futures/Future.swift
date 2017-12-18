import Foundation
import Dispatch

/// A future is an entity that stands inbetween the provider and receiver.
///
/// A provider returns a future type that will be completed with the future result
///
/// A future can also contain an error, rather than a result.
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/)
public final class Future<T>: FutureType {
    /// Future expectation type
    public typealias Expectation = T

    /// The future's result will be stored
    /// here when it is resolved.
    private var result: Result?

    /// Contains information about callbacks
    /// waiting for this future to complete
    private struct Awaiter {
        let callback: ResultCallback
    }

    /// A list of all handlers waiting to 
    private var awaiters: [Awaiter]

    /// Creates a new, uncompleted, unprovoked future
    /// Can only be created by a Promise, so this is hidden
    internal init() {
        awaiters = []
        result = nil
    }

    /// Pre-filled promise future
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#futures-without-promise)
    public convenience init(_ result: T) {
        self.init()
        self.result = .expectation(result)
    }

    /// Pre-filled failed promise
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#futures-without-promise)
    public convenience init(error: Error) {
        self.init()
        self.result = .error(error)
    }
    
    /// `true` if the future is already completed.
    public var isCompleted: Bool {
        return result != nil
    }

    /// Awaits the expectation without blocking other tasks
    /// on the `EventLoop`.
    public func await(on worker: Worker) throws -> Expectation {
        while result == nil {
            worker.eventLoop.run()
        }
        switch result! {
        case .error(let error): throw error
        case .expectation(let exp): return exp
        }
    }

    /// Completes the result, notifying awaiters.
    internal func complete(with result: Result) {
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

    /// Locked method for adding an awaiter
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#adding-awaiters-to-all-results)
    public func addAwaiter(callback: @escaping ResultCallback) {
        if let result = self.result {
            callback(result)
        } else {
            let awaiter = Awaiter(callback: callback)
            awaiters.append(awaiter)
        }
    }
}
