public extension DirectoryConfig {
    @available(*, deprecated, renamed: "detect")
    public static var `default`: () -> DirectoryConfig {
        return DirectoryConfig.detect
    }
}
