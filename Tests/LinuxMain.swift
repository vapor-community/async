#if os(Linux)

import XCTest
@testable import AsyncTests

XCTMain([
    testCase(EventLoopTests.allTests),
    testCase(FutureTests.allTests),
    testCase(StreamTests.allTests),
    testCase(FileTests.allTests),
])

#endif
