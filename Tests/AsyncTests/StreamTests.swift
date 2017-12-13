import XCTest
import Async

final class StreamTests : XCTestCase {
    func testPipeline() throws {
        let numberEmitter = EmitterStream(Int.self)

        var squares: [Int] = []
        var reported = false

        numberEmitter.map(to: Int.self) { int in
            return int * int
        }.drain { square in
            squares.append(square)
            if square == 9 {
                throw CustomError()
            }
        }.catch { error in
            reported = true
            XCTAssert(error is CustomError)
        }

        numberEmitter.emit(1)
        numberEmitter.emit(2)
        numberEmitter.emit(3)

        XCTAssertEqual(squares, [1, 4, 9])
        XCTAssert(reported)
    }

    func testDelta() throws {
        let numberEmitter = EmitterStream<Int>()
        let splitter = OutputStreamSplitter(numberEmitter)

        var output: [Int] = []

        splitter.split { int in
            output.append(int)
        }.split { int in
            output.append(int)
        }.catch { err in
            XCTFail("\(err)")
        }

        numberEmitter.emit(1)
        numberEmitter.emit(2)
        numberEmitter.emit(3)

        XCTAssertEqual(output, [1, 1, 2, 2, 3, 3])
    }

    func testErrorChaining() throws {
        let numberEmitter = EmitterStream(Int.self)

        var results: [Int] = []
        var reported = false

        numberEmitter.map(to: Int.self) { int in
            return int * 2
        }.map(to: Int.self) { int in
            return int / 2
        }.drain { res in
            if res == 3 {
                throw CustomError()
            }
            results.append(res)
        }.catch { error in
            reported = true
            XCTAssert(error is CustomError)
        }

        numberEmitter.emit(1)
        numberEmitter.emit(2)
        numberEmitter.emit(3)

        XCTAssertEqual(results, [1, 2])
        XCTAssert(reported)
    }

    func testCloseChaining() throws {
        let numberEmitter = EmitterStream(Int.self)

        var results: [Int] = []
        var closed = false

        numberEmitter.map(to: Int.self) { int in
            return int * 2
        }.map(to: Int.self) { int in
            return int / 2
        }.drain { res in
            results.append(res)
        }.catch { error in
            XCTFail()
        }.finally {
            closed = true
        }

        numberEmitter.emit(1)
        numberEmitter.emit(2)
        numberEmitter.emit(3)

        numberEmitter.close()

        XCTAssertEqual(results, [1, 2, 3])
        XCTAssert(closed)
    }


    static let allTests = [
        ("testPipeline", testPipeline),
        ("testDelta", testDelta),
        ("testErrorChaining", testErrorChaining),
        ("testCloseChaining", testCloseChaining),
    ]
}
