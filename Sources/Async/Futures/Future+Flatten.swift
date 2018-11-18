/// A closure that returns a future.
public typealias LazyFuture<T> = () -> (Future<T>)

extension Collection {
    /// Flattens an array of lazy futures into a future with an array of results.
    /// note: each subsequent future will wait for the previous to
    /// complete before starting.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func syncFlatten<T>() -> Future<[T]> where Element == LazyFuture<T> {
        let promise = Promise<[T]>()
        
        var elements: [T] = []
        elements.reserveCapacity(self.count)
        
        var iterator = makeIterator()
        func handle(_ future: LazyFuture<T>) {
            future().do { res in
                elements.append(res)
                if let next = iterator.next() {
                    handle(next)
                } else {
                    promise.complete(elements)
                }
            }.catch { error in
                promise.fail(error)
            }
        }
        
        if let first = iterator.next() {
            handle(first)
        } else {
            promise.complete(elements)
        }
        
        return promise.future
    }
}

extension Collection where Element == LazyFuture<Void> {
    /// Flattens an array of lazy void futures into a single void future.
    /// note: each subsequent future will wait for the previous to
    /// complete before starting.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func syncFlatten() -> Future<Void> {
        let flatten: Future<[Void]> = self.syncFlatten()
        return flatten.transform(to: ())
    }
}

extension Collection where Element : FutureType {
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

extension Collection where Element == Future<Void> {
    /// Flattens an array of void futures into a single one.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func flatten() -> Future<Void> {
        let flatten: Future<[Void]> = self.flatten()
        return flatten.map(to: Void.self) { _ in return }
    }
}
