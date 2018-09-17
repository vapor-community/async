#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

/// Contains a configured working directory.
public struct DirectoryConfig {
    /// The working directory
    public let workDir: String

    /// Create a new directory config.
    public init(workDir: String) {
        self.workDir = workDir
    }

    /// Creates a directory config with default working directory.
    public static func detect() -> DirectoryConfig {
        var workDir: String

        let cwd = getcwd(nil, Int(PATH_MAX))
        defer {
            free(cwd)
        }
        if let cwd = cwd, let string = String(validatingUTF8: cwd) {
            workDir = string
        } else {
            workDir = "./"
        }

        let standardPaths = [".build", "Packages", "Sources"]
        for path in standardPaths {
            if workDir.contains(path){
                workDir = workDir.components(separatedBy:"/\(path)").first!
                break
            }
        }

        return DirectoryConfig(
            workDir: workDir.hasSuffix("/") ? workDir : workDir + "/"
        )
    }
}
