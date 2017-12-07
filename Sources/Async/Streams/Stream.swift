/// A `Stream` represents a processing stage—which is both a `InputStream`
/// and a `OutputStream` and obeys the contracts of both.
public typealias Stream = InputStream & OutputStream
