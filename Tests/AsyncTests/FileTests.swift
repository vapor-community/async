import XCTest
import Async

class FileTests: XCTestCase {
    func testFileRead() throws {
        let file = try File(on: DefaultEventLoop(label: "junk-drawer")).read(at: CommandLine.arguments[0], chunkSize: 128).blockingAwait()
        XCTAssertGreaterThan(file.count, 512)
    }
    
    func testExists() {
        try XCTAssert(File(on: DefaultEventLoop(label: "junk-drawer")).directoryExists(at: "."))
    }
    
    static var allTests = [
        ("testFileRead", testFileRead),
        ("testExists", testExists),
    ]
}
