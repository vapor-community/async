import Foundation
import Dispatch

/// A future is an entity that stands inbetween the provider and receiver.
///
/// A provider returns a future type that will be completed with the future result
///
/// A future can also contain an error, rather than a result.
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/)
public struct Future<T>: FutureType {
    /// Future expectation type
    public typealias Expectation = T
    
    enum Storage {
        case completed(Result)
        case promise(Promise<T>)
    }

    /// The future's result will be stored
    /// here when it is resolved.
    private var storage: Storage

    /// Pre-filled promise future
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#futures-without-promise)
    public init(_ result: T) {
        self.storage = .completed(.expectation(result))
    }

    /// Pre-filled failed promise
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#futures-without-promise)
    public init(error: Error) {
        self.storage = .completed(.error(error))
    }
    
    internal init(referring promise: Promise<T>) {
        self.storage = .promise(promise)
    }
    
    /// `true` if the future is already completed.
    public var isCompleted: Bool {
        switch storage {
        case .completed(_): return true
        case .promise(let promise): return promise.isCompleted
        }
    }

    /// Awaits the expectation without blocking other tasks
    /// on the `EventLoop`.
    public func await(on worker: Worker) throws -> Expectation {
        let result: Result
        
        switch storage {
        case .completed(let completed):
            result = completed
        case .promise(let promise):
            while promise.result == nil {
                worker.eventLoop.run()
            }
            
            result = promise.result!
        }
        
        switch result {
        case .error(let error): throw error
        case .expectation(let exp): return exp
        }
    }
    
    /// Asserts the future is completed and the result must be returned now
    ///
    /// Throws an error if the future wasn't completed or contains an error
    public func requireCompleted() throws -> Expectation {
        let result: Result
        
        switch storage {
        case .completed(let completed):
            result = completed
        case .promise(let promise):
            guard let promiseResult = promise.result else {
                throw UncompletedFuture()
            }
            
            result = promiseResult
        }
        
        switch result {
        case .error(let error): throw error
        case .expectation(let exp): return exp
        }
    }

    /// Locked method for adding an awaiter
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#adding-awaiters-to-all-results)
    public func addAwaiter(callback: @escaping FutureResultCallback<Expectation>) {
        switch storage {
        case .completed(let result):
            callback(result)
        case .promise(let promise):
            if let result = promise.result {
                callback(result)
            } else {
                if promise.firstAwaiter == nil {
                    promise.firstAwaiter = .init(callback: callback)
                } else {
                    promise.otherAwaiters.append(.init(callback: callback))
                }
            }
        }
    }
}

public extension Future where T: Equatable {
    /// Assert the value being passed along the chain is equal to the value passed in
    /// Return true if it is, false if it's not
    public func assertEquals(_ val: T) -> Future<Bool> {
        return self.map(to: Bool.self) { (currentVal) in
            return currentVal == val
        }
    }
}

public extension Future where T == Bool {
    
    /// Acts guards against whatever it's being chained with
    /// If true, continue the chain
    /// Else, throw the supplied error
    public func `guard`(elseThrow error: Error) -> Future<Bool> {
        return self.map(to: Bool.self) { (check) in
            guard check else {throw error}
            return check
        }
    }
}

/// Thrown when a future is asserted as completed but wasn't completed
fileprivate struct UncompletedFuture: Error {}
