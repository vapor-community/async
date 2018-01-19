// MARK: Convenience
extension Future {
    /// Globally available initializer for mimicking behavior of calling `return future.flatMao`
    /// where no starting future is available.
    ///
    /// This allows you to convert any non-throwing, future-return method into a
    /// closure that accepts throwing and returns a future.
    public static func flatMap(_ callback: @escaping () throws -> Future<Expectation>) -> Future<Expectation> {
        let promise = Promise<Expectation>()

        do {
            try callback().addAwaiter { result in
                switch result {
                case .error(let error):
                    promise.fail(error)
                case .expectation(let expectation):
                    promise.complete(expectation)
                }
            }
        } catch {
            promise.fail(error)
        }

        return promise.future
    }

    /// Globally available initializer for mimicking behavior of calling `return future.flatMao`
    /// where no starting future is available.
    ///
    /// This allows you to convert any non-throwing, future-return method into a
    /// closure that accepts throwing and returns a future.
    public static func map(_ callback: @escaping () throws -> Expectation) -> Future<Expectation> {
        let promise = Promise<Expectation>()

        do {
            try promise.complete(callback())
        } catch {
            promise.fail(error)
        }

        return promise.future
    }
}
