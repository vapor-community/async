/// An event loop timeout.
public struct EventLoopTimeout {
    /// Double-represented seconds
    private var storage: Double

    /// no prefix    100
    public var seconds: Int {
        return Int(storage)
    }

    /// milli (m)    10-3
    public var milliseconds: Int {
        return Int(storage * 1_000)
    }

    /// micro (µ)    10-6
    public var microseconds: Int {
        return Int(storage * 1_000_000)
    }

    /// nano (n)    10-9
    public var nanoseconds: Int {
        return Int(storage * 1_000_000_000)
    }

    /// Create a new Timeout with seconds.
    public static func seconds(_ seconds: Int) -> EventLoopTimeout {
        return .init(storage: Double(seconds))
    }

    /// Create a new Timeout with millseconds.
    public static func milliseconds(_ milliseconds: Int) -> EventLoopTimeout {
        return .init(storage: Double(milliseconds) / 1_000)
    }

    /// Create a new Timeout with millseconds.
    public static func microseconds(_ milliseconds: Int) -> EventLoopTimeout {
        return .init(storage: Double(milliseconds) / 1_000_000)
    }

    /// Create a new Timeout with millseconds.
    public static func nanoseconds(_ milliseconds: Int) -> EventLoopTimeout {
        return .init(storage: Double(milliseconds) / 1_000_000_000)
    }
}
