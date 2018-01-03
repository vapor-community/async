import XCTest
import Async

final class EventLoopTests : XCTestCase {
    func testAsync() throws {
        print("\(#line)")
        let loop = try DefaultEventLoop(label: "codes.vapor.async.test.async")
        print("\(#line)")

        let socket = loop.onTimeout(timeout: 100) { _ in /* fake socket */ }
        print("\(#line)")
        socket.resume()
        print("\(#line)")
        
        var nums: [Int] = []

        func recurse(depth: Int = 0) {
            guard depth < 32 else {
                return
            }

            loop.async {
                nums.append(depth)
                recurse(depth: depth + 1)
            }
        }

        recurse()
        loop.run()
        XCTAssert(nums.count == 32)
        XCTAssert(nums.first == 0)
        XCTAssert(nums.last == 31)
    }

    func testTimers() throws {
        let loop = try DefaultEventLoop(label: "codes.vapor.async.test.timers")

        let promise = Promise(Void.self)

        var count = 0
        var source: EventSource?
        source = loop.onTimeout(timeout: 100) { eof in
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
        ("testAsync", testAsync),
        ("testTimers", testTimers),
    ]
}
