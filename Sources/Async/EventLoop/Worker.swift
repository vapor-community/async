/// Has an EventLoop.
public protocol Worker {
    /// This worker's event loop. All async work done
    /// on this worker _must_ occur on its event loop.
    var eventLoop: EventLoop { get }
}
