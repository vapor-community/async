/// Callback for accepting a result.
public typealias FutureResultCallback<T> = (FutureResult<T>) -> ()

/// A future result type.
/// Concretely implemented by `Future<T>`
public protocol FutureType {
    associatedtype Expectation
    
    /// This future's result type.
    typealias Result = FutureResult<Expectation>
    
    func addAwaiter(callback: @escaping FutureResultCallback<Expectation>)
}

public extension Future {
    /// Chains a future to a promise of the same type.
    func chain(to promise: Promise<Expectation>) {
        addAwaiter { result in
            switch result {
            case .error(let error): promise.fail(error)
            case .expectation(let expectation): promise.complete(expectation)
            }
        }
    }
}
