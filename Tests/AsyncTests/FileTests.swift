import XCTest
import Async

class FileTests: XCTestCase {
    func testFileRead() throws {
        let file = try File(on: DispatchEventLoop(label: "junk-drawer")).read(at: CommandLine.arguments[0], chunkSize: 128).blockingAwait()
        XCTAssertGreaterThan(file.count, 512)
    }
    
    static var allTests = [
        ("testFileRead", testFileRead),
    ]
}
