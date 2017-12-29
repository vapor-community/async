import XCTest
import Async

final class EventLoopTests : XCTestCase {
    func testAsync() throws {
        let loop = try DefaultEventLoop(label: "codes.vapor.async.test.async")
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


    static let allTests = [
        ("testAsync", testAsync),
    ]
}
