/// A closure that returns a future.
public typealias LazyFuture<T> = () -> (Future<T>)

/// FIXME: some way to make this generic?
extension Array where Element == LazyFuture<Void> {
    /// Flattens an array of lazy futures into a future with an array of results.
    /// note: each subsequent future will wait for the previous to
    /// complete before starting.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func syncFlatten() -> Future<Void> {
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

extension Array where Element: FutureType {
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
            element.do { result in
                elements.append(result)
                
                if elements.count == self.count {
                    promise.complete(elements)
                }
            }.catch(promise.fail)
        }

        return promise.future
    }
}


extension Array where Element: FutureType {
    /// See FutureType.map
    public func map<T>(_ callback: @escaping ([Element.Expectation]) throws -> T) -> Future<T> {
        return flatten().map(callback)
    }

    /// See FutureType.then
    public func then<T>(_ callback: @escaping ([Element.Expectation]) throws -> T) -> Future<T.Expectation>
        where T: FutureType
    {
        return flatten().then(callback)
    }
}


extension Array where Element: FutureType, Element.Expectation == Void {
    /// See FutureType.map
    public func map<T>(_ callback: @escaping () throws -> T) -> Future<T> {
        return flatten().map { _ in
            return try callback()
        }
    }

    /// See FutureType.then
    public func then<T>(_ callback: @escaping () throws -> Future<T>) -> Future<T> {
        return flatten().then { _ in
            return try callback()
        }
    }

    /// Flattens an array of void futures into a single one.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/advanced-futures/#combining-multiple-futures)
    public func flatten() -> Future<Void> {
        return then { _ in
            return Future.done
        }
    }
}

/// MARK: Variadic

/// Calls the supplied callback when both futures have completed.
public func then<A, B, T>(
    _ futureA: A, _ futureB: B, _ callback: @escaping (A.Expectation, B.Expectation) throws -> (T)
) -> Future<T.Expectation>
    where A: FutureType, B: FutureType, T: FutureType
{
    return futureA.then { a -> Future<T.Expectation> in
        return futureB.then { b -> T in
            return try callback(a, b)
        }
    }
}

/// Calls the supplied callback when all three futures have completed.
public func then<A, B, C, T>(
    _ futureA: A, _ futureB: B, _ futureC: C, _ callback: @escaping (A.Expectation, B.Expectation, C.Expectation) throws -> (T)
) -> Future<T.Expectation>
where A: FutureType, B: FutureType, C: FutureType, T: FutureType
{
    return futureA.then { a -> Future<T.Expectation> in
        return futureB.then { b -> Future<T.Expectation> in
            return futureC.then { c -> T in
                return try callback(a, b, c)
            }
        }
    }
}
