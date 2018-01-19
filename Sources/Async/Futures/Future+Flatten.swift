/// A closure that returns a future.
public typealias LazyFuture<T> = () -> (Future<T>)

/// FIXME: some way to make this generic?
extension Array where Element == LazyFuture<Void> {
    /// Flattens an array of lazy futures into a future with an array of results.
    /// note: each subsequent future will wait for the previous to
    /// complete before starting.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func syncFlatten() -> Signal {
        let promise = Promise<Void>()
        
        var iterator = makeIterator()
        func handle(_ future: LazyFuture<Void>) {
            future().do { res in
                if let next = iterator.next() {
                    handle(next)
                } else {
                    promise.complete()
                }
            }.catch { error in
                promise.fail(error)
            }
        }
        
        if let first = iterator.next() {
            handle(first)
        } else {
            promise.complete()
        }
        
        return promise.future
    }
}

extension Array where Element : FutureType {
    /// Flattens an array of futures into a future with an array of results.
    /// note: the order of the results will match the order of the
    /// futures in the input array.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func flatten() -> Future<[Element.Expectation]> {
        var elements: [Element.Expectation] = []

        guard count > 0 else {
            return Future(elements)
        }

        let promise = Promise<[Element.Expectation]>()
        elements.reserveCapacity(self.count)

        for element in self {
            element.addAwaiter { result in
                switch result {
                case .error(let error): promise.fail(error)
                case .expectation(let expectation):
                    elements.append(expectation)
                    
                    if elements.count == self.count {
                        promise.complete(elements)
                    }
                }
            }
        }

        return promise.future
    }
}

extension Array where Element == Signal {
    /// Flattens an array of void futures into a single one.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func flatten() -> Signal {
        let flatten: Future<[Void]> = self.flatten()
        return flatten.map(to: Void.self) { _ in return }
    }
}
