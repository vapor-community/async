#if os(Linux)

import XCTest
@testable import AsyncTests

XCTMain([
    testCase(FutureTests.allTests),
    testCase(StreamTests.allTests),
])

#endif
