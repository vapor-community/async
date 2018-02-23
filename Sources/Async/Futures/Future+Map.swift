extension Future {
    /// Maps a future to a future of a different type.
    /// The result returned within should be non-future type.
    ///
    /// [Learn More →](https://docs.vapor.codes/3.0/async/promise-future-introduction/#mapping-results)
    public func map<T>(to type: T.Type, _ callback: @escaping (Expectation) throws -> T) -> Future<T> {
        let promise = Promise(T.self)

        self.do { expectation in
            do {
                let mapped = try callback(expectation)
                promise.complete(mapped)
            } catch {
                promise.fail(error)
            }
        }.catch { error in
            promise.fail(error)
        }

        return promise.future
    }

    /// Maps a future to a future of a different type.
    /// The result returned within should be a future.
    public func flatMap<Wrapped>(
        to type: Wrapped.Type,
        _ callback: @escaping (Expectation) throws -> Future<Wrapped>
    ) -> Future<Wrapped> {
        let promise = Promise<Wrapped>()

        self.do { expectation in
            do {
                let mapped = try callback(expectation)
                mapped.chain(to: promise)
            } catch {
                promise.fail(error)
            }
        }.catch { error in
            promise.fail(error)
        }

        return promise.future
    }
}

/// Applies nil coalescing to a future's optional and a concrete type
public func ??<T>(lhs: Future<T?>, rhs: T) -> Future<T> {
    return lhs.map(to: T.self) { value in
        return value ?? rhs
    }
}

/// MARK: Same type

extension Future {
    /// See `Future.map`
    public func map(_ callback: @escaping (Expectation) throws -> Expectation) -> Future<Expectation> {
        return map(to: Expectation.self, callback)
    }

    /// See `Future.flatMap`
    public func flatMap(_ callback: @escaping (Expectation) throws -> Future<Expectation>) -> Future<Expectation> {
        return flatMap(to: Expectation.self, callback)
    }
}

/// MARK: Array

extension Collection where Element: FutureType {
    /// See `Future.map`
    public func map<T>(to type: T.Type, _ callback: @escaping ([Element.Expectation]) throws -> T) -> Future<T> {
        return flatten().map(to: T.self, callback)
    }

    /// See `Future.flatMap`
    public func flatMap<T>(to type: T.Type, _ callback: @escaping ([Element.Expectation]) throws -> Future<T>) -> Future<T> {
        return flatten().flatMap(to: T.self, callback)
    }
}

extension Collection where Element == Future<Void> {
    /// See `Future.map`
    public func map<T>(to type: T.Type, _ callback: @escaping () throws -> T) -> Future<T> {
        return flatten().map(to: T.self) { _ in
            return try callback()
        }
    }


    /// See `Future.flatMap`
    public func flatMap<T>(to type: T.Type, _ callback: @escaping () throws -> Future<T>) -> Future<T> {
        return flatten().flatMap(to: T.self) { _ in
            return try callback()
        }
    }
}

/// MARK: Variadic

/// Calls the supplied callback when both futures have completed.
public func map<A, B, Result>(
    to result: Result.Type,
    _ futureA: Future<A>,
    _ futureB: Future<B>,
    _ callback: @escaping (A, B) throws -> (Result)
) -> Future<Result> {
    return futureA.flatMap(to: Result.self) { a in
        return futureB.map(to: Result.self) { b in
            return try callback(a, b)
        }
    }
}

/// Calls the supplied callback when all three futures have completed.
public func map<A, B, C, Result>(
    to result: Result.Type,
    _ futureA: Future<A>,
    _ futureB: Future<B>,
    _ futureC: Future<C>,
    _ callback: @escaping (A, B, C) throws -> (Result)
    ) -> Future<Result> {
    return futureA.flatMap(to: Result.self) { a in
        return futureB.flatMap(to: Result.self) { b in
            return futureC.map(to: Result.self) { c in
                return try callback(a, b, c)
            }
        }
    }
}

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


/// MARK: Catch

extension Future {
    /// Calls the supplied closure if the chained Future resolves to an Error.
    ///
    /// The closure gives you a chance to rectify the error (returning the desired expectation)
    /// or to re-throw or throw a different error.
    ///
    /// The callback expects a non-Future return (if not throwing instead). See `catchFlatMap` for a Future return.
    public func catchMap(_ callback: @escaping (Error) throws -> (Expectation)) -> Future<Expectation> {
        let promise = Promise(Expectation.self)
        addAwaiter { result in
            switch result {
            case .error(let error):
                do {
                    try promise.complete(callback(error))
                } catch {
                    promise.fail(error)
                }
            case .expectation(let e): promise.complete(e)
            }
        }
        return promise.future
    }


    /// Calls the supplied closure if the chained Future resolves to an Error.
    ///
    /// The closure gives you a chance to rectify the error (returning the desired expectation)
    /// or to re-throw or throw a different error.
    ///
    /// The callback expects a Future return (if not throwing instead). See `catchMap` for a non-Future return.
    ///
    ///      return conn.query("BEGIN TRANSACTION").flatMap {
    ///          return transaction.run(on: connection).flatMap {
    ///              return conn.query("END TRANSACTION")
    ///          }.catchFlatMap { error in
    ///              return conn.query("ROLLBACK").map {
    ///                  throw error
    ///              }
    ///          }
    ///      }
    ///
    public func catchFlatMap(_ callback: @escaping (Error) throws -> (Future<Expectation>)) -> Future<Expectation> {
        let promise = Promise(Expectation.self)
        addAwaiter { result in
            switch result {
            case .error(let error):
                do {
                    try callback(error).chain(to: promise)
                } catch {
                    promise.fail(error)
                }
            case .expectation(let e): promise.complete(e)
            }
        }
        return promise.future
    }
}
