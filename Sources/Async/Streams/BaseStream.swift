/// A stream is both an InputStream and an OutputStream
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#implementing-an-example-stream)
public typealias Stream = InputStream & OutputStream

/// Base stream protocol. Simply handles errors.
/// All streams are expected to reset themselves
/// after reporting an error and be ready for
/// additional incoming data.
///
/// [Learn More →](https://docs.vapor.codes/3.0/async/streams-introduction/#implementing-an-example-stream)
public protocol BaseStream: class { }
