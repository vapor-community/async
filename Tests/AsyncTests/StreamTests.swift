import XCTest
import Async

final class StreamTests : XCTestCase {
    func testPipeline() throws {
        var squares: [Int] = []
        var reported = false
        var closed = false

        let numberEmitter = EmitterStream(Int.self)

        numberEmitter.map(to: Int.self) { num -> Int in
            return num * num
        }.drain { req in
            req.request(count: .max)
        }.output { num in
            squares.append(num)
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

        numberEmitter.split { int in
            output.append(int)
        }.drain { req in
            req.request(count: .max)
        }.output { int in
            output.append(int)
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

        numberEmitter.map(to: Int.self) { int in
            return int * 2
        }.map(to: Int.self) { int in
            return int / 2
        }.drain { req in
            req.request(count: .max)
        }.output { res in
            if res == 3 {
                throw CustomError()
            }
            results.append(res)
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

        numberEmitter.map(to: Int.self) { int in
            return int * 2
        }.map(to: Int.self) { int in
            return int / 2
        }.drain { req in
            req.request(count: .max)
        }.output { res in
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

    func testTranslatingStream() throws {
        let emitter = EmitterStream([Int].self)
        let loop = try KqueueEventLoop(label: "codes.vapor.test.translating")

        let stream = ArrayChunkingStream<Int>(size: 3).stream(on: loop)
        emitter.output(to: stream)

        var upstream: ConnectionContext?
        var chunks: [[Int]] = []

        stream.drain { req in
            upstream = req
        }.output { chunk in
            chunks.append(chunk)
            upstream?.request()
        }.catch { error in
            XCTFail("\(error)")
        }.finally {
            print("closed")
        }

        upstream?.request()

        // test insufficient, then sufficient
        XCTAssertEqual(chunks.count, 0)
        emitter.emit([1, 2])
        XCTAssertEqual(chunks.count, 0)
        emitter.emit([3])
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0], [1, 2, 3])

        // test sufficient
        XCTAssertEqual(chunks.count, 1)
        emitter.emit([4, 5, 6])
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0], [1, 2, 3])
        XCTAssertEqual(chunks[1], [4, 5, 6])

        // test insufficient, then excess
        XCTAssertEqual(chunks.count, 2)
        emitter.emit([7, 8])
        XCTAssertEqual(chunks.count, 2)
        emitter.emit([9, 10])
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0], [1, 2, 3])
        XCTAssertEqual(chunks[1], [4, 5, 6])
        XCTAssertEqual(chunks[2], [7, 8, 9])

        // test excess
        emitter.emit([11, 12, 13, 14, 15])
        XCTAssertEqual(chunks.count, 5)
        XCTAssertEqual(chunks[0], [1, 2, 3])
        XCTAssertEqual(chunks[1], [4, 5, 6])
        XCTAssertEqual(chunks[2], [7, 8, 9])
        XCTAssertEqual(chunks[3], [10, 11, 12])
        XCTAssertEqual(chunks[4], [13, 14, 15])
    }

    func testTranslatingStreamOverflow() throws {
        let emitter = EmitterStream([Int].self)
        let loop = try KqueueEventLoop(label: "codes.vapor.test.translating")

        let socket = loop.onTimeout(timeout: 100) { _ in /* fake socket */ }
        socket.resume()

        Thread.async { loop.runLoop() }

        let stream = ArrayChunkingStream<Int>(size: 2).stream(on: loop)
        emitter.output(to: stream)

        var upstream: ConnectionContext?
        var chunks: [[Int]] = []


        let count = 10_000
        let exp = expectation(description: "\(count) chunks")


        stream.drain { req in
            upstream = req
        }.output { chunk in
            chunks.append(chunk)
            if chunks.count >= count {
                exp.fulfill()
            } else {
                upstream?.request()
            }
        }.catch { error in
            XCTFail("\(error)")
        }.finally {
            print("closed")
        }

        upstream?.request()

        let huge = [Int].init(repeating: 5, count: count * 2)
        emitter.emit(huge)

        waitForExpectations(timeout: 5)
    }

    static let allTests = [
        ("testPipeline", testPipeline),
        ("testDelta", testDelta),
        ("testErrorChaining", testErrorChaining),
        ("testCloseChaining", testCloseChaining),
    ]
}
