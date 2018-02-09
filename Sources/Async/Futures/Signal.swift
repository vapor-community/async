@available(*, renamed: "Future<Void>")
public typealias Signal = Future<Void>

// MARK: Void

extension Future where T == Void {
    /// Pre-completed void future.
    public static var done: Signal {
        return _done
    }
}

private let _done = Future(())
