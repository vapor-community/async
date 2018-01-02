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
    
    func testMapError() throws {
        
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
    
    func testFutureStream() {
        let stream = FutureStream<Int, String> { int in
            return Future(int.description)
        }
        
        XCTAssertEqual(try stream.transform(3).blockingAwait(), "3")
    }
    
    func testConnectingStream() {
        let numberEmitter = EmitterStream(Int.self)
        
        var reached = false
        var i = 0
        let max = 100
        
        let drainStream = DrainStream(Int.self, onConnect: { upstream in
            upstream.request(count: .max)
        }, onInput: { int in
            XCTAssertEqual(i, int)
        }, onError: { error in
            XCTFail("\(error)")
        }, onClose: {
            XCTAssert(i == max)
            reached = true
        })
        
        let stream = ConnectingStream<Int>()
        numberEmitter.stream(to: stream).output(to: drainStream)
        
        while i < max {
            numberEmitter.emit(i)
            i += 1
        }
        
        numberEmitter.close()
        
        XCTAssert(reached)
    }
    
    func testClosureStream() {
        var downstream: AnyInputStream<Int>?
        var upstream: ConnectionContext?
        var reached = false
        var i = 0
        let max = 100
        
        let closureStream = ClosureStream<Int>(onInput: { event in
            switch event {
            case .next(let int):
                XCTAssertEqual(int, max)
                downstream?.next(int ^ .max)
            case .connect(let _upstream):
                upstream = _upstream
            case .close:
                downstream?.close()
            case .error(let error):
                XCTFail("\(error)")
            }
        }, onOutput: { _downstream in
            downstream = _downstream
        }, onConnection: { event in
            switch event {
            case .cancel: break
            case .request(let i):
                upstream?.request(count: i)
            }
        })
        
        let numberEmitter = EmitterStream(Int.self)
        numberEmitter.output(to: closureStream)
        
        closureStream.drain { upstream in
            upstream.request(count: .max)
        }.output { int in
            XCTAssertEqual(int ^ .max, i)
        }.catch { error in
            XCTFail("\(error)")
        }.finally {
            reached = true
        }
        
        while i < max {
            numberEmitter.emit(i)
            i += 1
        }
        
        numberEmitter.close()
        XCTAssert(reached)
    }

    static let allTests = [
        ("testPipeline", testPipeline),
        ("testDelta", testDelta),
        ("testErrorChaining", testErrorChaining),
        ("testCloseChaining", testCloseChaining),
        ("testFutureStream", testFutureStream),
        ("testCloseChaining", testCloseChaining),
        ("testCloseChaining", testCloseChaining),
    ]
}
