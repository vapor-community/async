/// Applies nil coalescing to a future's optional and a concrete type
public func ??<T>(lhs: Future<T?>, rhs: T) -> Future<T> {
    return lhs.map(to: T.self) { value in
        return value ?? rhs
    }
}
