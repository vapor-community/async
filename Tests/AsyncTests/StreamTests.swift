import XCTest
import Async

final class StreamTests : XCTestCase {
    func testPipeline() throws {
        var squares: [Int] = []
        var reported = false
        var closed = false

        let numberEmitter = EmitterStream(Int.self)

        numberEmitter.map { num -> Int in
            return num * num
        }.drain(1) { num, req in
            squares.append(num)
            req.requestOutput()
            if num == 9 {
                throw CustomError()
            }
        }.catch { error in
            reported = true
            XCTAssert(error is CustomError)
        }.finally {
            closed = true
        }

        numberEmitter.emit(1)
        numberEmitter.emit(2)
        numberEmitter.emit(3)

        numberEmitter.close()

        XCTAssertEqual(squares, [1, 4, 9])
        XCTAssert(reported)
        XCTAssert(closed)
    }

    func testDelta() throws {
        let numberEmitter = EmitterStream<Int>()

        var output: [Int] = []

        numberEmitter.split { int, req in
            output.append(int)
            req.requestOutput()
        }.drain { int, req in
            output.append(int)
            req.requestOutput()
        }.catch { err in
            XCTFail("\(err)")
        }.finally {
            // closed
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

        numberEmitter.map { int in
            return int * 2
        }.map { int in
            return int / 2
        }.drain { res, req in
            if res == 3 {
                throw CustomError()
            }
            results.append(res)
            req.requestOutput()
        }.catch { error in
            reported = true
            XCTAssert(error is CustomError)
        }.finally {
            // closed
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

        numberEmitter.map { int in
            return int * 2
        }.map { int in
            return int / 2
        }.drain { res, req in
            results.append(res)
            req.requestOutput()
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
