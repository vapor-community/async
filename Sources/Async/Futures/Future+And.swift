import Foundation

extension Future {
    /// Merges the result of two futures into a tuple.
    public func and<S>(_ otherFuture: Future<S>) -> Future<(T, S)> {
        return self.flatMap(to: (T, S).self, { (thisExpectation: T) -> Future<(T, S)> in
            return otherFuture.map(to: (T, S).self, { (otherExpectation: S) in
                return (thisExpectation, otherExpectation)
            })
        })
    }

    /// Merges the result of three futures into a tuple.
    public func and<S, V>(_ otherFuture: Future<S>, _ yetAnotherFuture: Future<V>) -> Future<(T, S, V)> {
        return self.and(otherFuture).flatMap(to: (T, S, V).self, { (tAndS) in
            let t = tAndS.0
            let s = tAndS.1
            return yetAnotherFuture.map(to: (T, S, V).self, { (v) in
                (t, s, v)
            })
        })
    }
}
