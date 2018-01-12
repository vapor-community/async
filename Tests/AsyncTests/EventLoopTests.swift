import XCTest
import Async

final class EventLoopTests : XCTestCase {
    func testTimers() throws {
        let loop = try DefaultEventLoop(label: "codes.vapor.async.test.timers")

        let promise = Promise(Void.self)

        var count = 0
        var source: EventSource?
        source = loop.onTimeout(milliseconds: 100) { eof in
            count += 1
            if count > 10 {
                promise.complete()
                source?.cancel()
                source = nil
            } else {
                loop.run()
            }
        }
        source?.resume()

        loop.run()
        try promise.future.blockingAwait()
    }

    static let allTests = [
        ("testTimers", testTimers),
    ]
}
