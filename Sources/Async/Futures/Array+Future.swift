/// A closure that returns a future.
public typealias LazyFuture<T> = () -> (Future<T>)

/// FIXME: some way to make this generic?
extension Array where Element == LazyFuture<Void> {
    /// Flattens an array of lazy futures into a future with an array of results.
    /// note: each subsequent future will wait for the previous to
    /// complete before starting.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func syncFlatten() -> Completable {
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


extension Array where Element: FutureType {
    /// See Future.map
    public func map<T>(
        to type: T.Type,
        _ callback: @escaping ([Element.Expectation]) throws -> T
    ) -> Future<T> {
        return flatten().map(to: T.self, callback)
    }

    /// See Future.then
    public func flatMap<T>(
        to type: T.Type,
        _ callback: @escaping ([Element.Expectation]) throws -> Future<T>
    ) -> Future<T> {
        return flatten().flatMap(to: T.self, callback)
    }
}

extension Array where Element == Completable {
    /// See Future.map
    public func map<T>(
        to type: T.Type,
        _ callback: @escaping () throws -> T
    ) -> Future<T> {
        return flatten().map(to: T.self) { _ in
            return try callback()
        }
    }

    /// See Future.then
    public func transform<T>(_ callback: @escaping () throws -> Future<T>) -> Future<T> {
        return flatten().flatMap(to: T.self, callback)
    }

    /// Flattens an array of void futures into a single one.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func flatten() -> Completable {
        return self.flatten().map(to: Void.self) { _ in return }
    }
}

/// MARK: Variadic

/// Calls the supplied callback when both futures have completed.
public func flatMap<A, B, Result>(
    to result: Result.Type,
    _ futureA: Future<A>,
    _ futureB: Future<B>,
    _ callback: @escaping (A, B) throws -> (Future<Result>)
) -> Future<Result> {
    return futureA.flatMap(to: Result.self) { a in
        return futureB.flatMap(to: Result.self) { b in
            return try callback(a, b)
        }
    }
}

/// Calls the supplied callback when all three futures have completed.
public func flatMap<A, B, C, Result>(
    to result: Result.Type,
    _ futureA: Future<A>,
    _ futureB: Future<B>,
    _ futureC: Future<C>,
    _ callback: @escaping (A, B, C) throws -> (Future<Result>)
) -> Future<Result> {
    return futureA.flatMap(to: Result.self) { a in
        return futureB.flatMap(to: Result.self) { b in
            return futureC.flatMap(to: Result.self) { c in
                return try callback(a, b, c)
            }
        }
    }
}
