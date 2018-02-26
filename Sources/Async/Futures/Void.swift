extension Future where T == Void {

    /// Convenience function for returning void inside a future
    public static var void: Void {
        return _void
    }
}

private let _void: Void = {}()
