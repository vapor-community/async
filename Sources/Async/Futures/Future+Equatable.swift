public extension Future where T: Equatable {
    public func equal(to value: T) -> Future<Bool> {
        return self.map(to: Bool.self) { current in
            return current == value
        }
    }
    
    public func equal(to value: T, or error: Error) throws -> Future<Bool> {
        return try self.map(to: Bool.self) { current in
            return current == value
        }.true(or: error)
    }

    public func notEqual(to value: T) -> Future<Bool> {
        return self.map(to: Bool.self) { current in
            return current != value
        }
    }
    
    public func notEqual(to value: T, or error: Error) throws -> Future<Bool> {
        return try self.map(to: Bool.self) { current in
            return current != value
        }.true(or: error)
    }
}
