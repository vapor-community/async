public extension Future where T == Bool {
    public func `true`(or error: Error) throws -> Future<Bool> {
        return self.map(to: Bool.self) { boolean in
            if !boolean {
                throw error
            }
            return boolean
        }
    }

    public func `false`(or error: Error) throws -> Future<Bool> {
        return self.map(to: Bool.self) { boolean in
            if boolean {
                throw error
            }
            return !boolean
        }
    }
}
