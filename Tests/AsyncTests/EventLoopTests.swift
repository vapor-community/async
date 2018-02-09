import XCTest
import Async

final class EventLoopTests : XCTestCase {
    func testTimers() throws {
        let loop = try DefaultEventLoop(label: "codes.vapor.async.test.timers")

        let promise = Promise(Void.self)

        var count = 0
        var source: EventSource?
        source = loop.onTimeout(timeout: .milliseconds(100)) { eof in
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

    func testTick() throws {
        let loop = try DefaultEventLoop(label: "codes.vapor.async.test.timers")
        var ticks = 0
        var done = false

        let source = loop.onNextTick { eof in
            ticks += 1
            done = eof
        }
        source.resume()
        XCTAssertEqual(ticks, 0)
        XCTAssertEqual(done, false)
        loop.run()
        XCTAssertEqual(ticks, 1)
        XCTAssertEqual(done, true)
        loop.run(timeout: .milliseconds(1))
        XCTAssertEqual(ticks, 1)
        XCTAssertEqual(done, true)
        loop.run(timeout: .milliseconds(1))
        XCTAssertEqual(ticks, 1)
        XCTAssertEqual(done, true)
    }

    func testFutureTick() throws {
        let promise = Promise(Void.self)

        var completed: Bool? = nil
        var error: Error? = nil

        promise.future.do {
            completed = true
        }.catch {
            error = $0
        }

        XCTAssertNil(completed)
        XCTAssertNil(error)

        let loop = try DefaultEventLoop(label: "codes.vapor.async.test.timers")
        promise.complete(onNextTick: loop)

        XCTAssertNil(completed)
        XCTAssertNil(error)

        loop.run()

        XCTAssertEqual(completed, true)
        XCTAssertNil(error)
    }

    static let allTests = [
        ("testTimers", testTimers),
        ("testTick", testTick),
        ("testFutureTick", testFutureTick),
    ]
}
