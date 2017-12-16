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

    func testTCPStream() throws {
        // let eventLoop = DispatchEventLoop()
        let eventLoop = try KqueueEventLoop()
        let tcpSocket = try TCPSocket(isNonBlocking: true)
        let tcpServer = try TCPServer(socket: tcpSocket)
        try tcpServer.start(hostname: "localhost", port: 8123, backlog: 128)
        let acceptStream = tcpServer.stream(on: eventLoop)

        var response = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi".utf8)

        acceptStream.drain { upstream in
            upstream.request(count: .max)
        }.output { client in
            let stream = client.stream(on: eventLoop)
            var upstream: ConnectionContext?
            stream.drain { context in
                upstream = context
                context.request(count: 1)
            }
            .output { buffer in
                stream.next(buffer)
//                response.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
//                    let buffer = UnsafeBufferPointer<UInt8>(start: bytes, count: response.count)
//                    stream.next(buffer)
//                }
                upstream?.request(count: 1)
            }.catch { error in
                XCTFail("\(error)")
            }.finally {
                print("CLOSED")
            }
        }.catch { error in
            XCTFail("\(error)")
        }.finally {
            print("CLOSED")
        }

        eventLoop.run()
    }

    static let allTests = [
        ("testPipeline", testPipeline),
        ("testDelta", testDelta),
        ("testErrorChaining", testErrorChaining),
        ("testCloseChaining", testCloseChaining),
    ]
}
