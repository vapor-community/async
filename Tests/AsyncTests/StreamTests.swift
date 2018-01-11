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

    func testTranslatingStream() throws {
        let emitter = EmitterStream([Int].self)
        let loop = try DefaultEventLoop(label: "codes.vapor.test.translating")

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
        let loop = try DefaultEventLoop(label: "codes.vapor.test.translating")

        let socket = loop.onTimeout(milliseconds: 100) { _ in /* fake socket */ }
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
            XCTFail("Never closed")
        }

        upstream?.request()

        let huge = [Int](repeating: 5, count: count * 2)
        emitter.emit(huge)

        waitForExpectations(timeout: 30)
    }
    
    func testPushStream() throws {
        var ints = [0, 1, 6, 1, 3, 5, 1, 9, 3, 7, 5, 1, 3, 2]
        
        var drainOffset = 0
        var closed = false
        
        let pushStream = PushStream<Int>()
        let drainStream = DrainStream<Int>(onInput: { input in
            XCTAssertEqual(ints[drainOffset], input)
            drainOffset += 1
        }, onClose: {
            closed = true
        })
        
        pushStream.output(to: drainStream)
        
        for int in ints {
            pushStream.next(int)
        }
        
        pushStream.request()
        XCTAssertEqual(drainOffset, 1)
        
        pushStream.request(count: 2)
        XCTAssertEqual(drainOffset, 3)
        
        ints.append(4)
        pushStream.next(4)
        
        pushStream.request(count: .max)
        XCTAssertEqual(drainOffset, ints.count)
        
        ints.append(5)
        pushStream.next(5)
        XCTAssertEqual(drainOffset, ints.count)
        
        pushStream.close()
        XCTAssert(closed)
    }
    
    func testByteParserStream() throws {
        var cases: [[UInt8]] = [
            [0, 0],
            [0, 1],
            [0, 2],
            [0, 3],
            [0, 4],
            [4, 1],
            [3, 1],
            [2, 1],
            [1, 1],
            [0, 1],
            [1, 2],
            [2, 2],
            [3, 2],
            [4, 2],
            [0, 1],
            [4, 3],
            [2, 1]
        ]
        
        let loop = try DefaultEventLoop(label: "codes.vapor.test.translating")
        
        let parser = SimpleByteParser().stream(on: loop)
        let emitter = EmitterStream<UnsafeBufferPointer<UInt8>>()
        var offset = 0
        var closed = false
        
        emitter.output(to: parser)
        
        parser.drain { upstream in
            upstream.request(count: .max)
        }.output { buffer in
            XCTAssertEqual(buffer, cases[offset])
            offset += 1
        }.finally {
            closed = true
            XCTAssertEqual(cases.count, offset)
        }
        
        func emit(_ data: [UInt8]) {
            data.withUnsafeBufferPointer(emitter.emit)
        }
        
        var data = cases.reduce([], +)
        var size = 0
        
        while data.count > 0 {
            let consume = min(data.count, size)
            
            emit(Array(data[..<consume]))
            
            data.removeFirst(consume)
            size += 1
        }
        
        emitter.close()
        
        XCTAssert(closed)
    }
    
    func testByteSerializerStream() throws {
        var cases: [[UInt8]] = [
            [0, 0],
            [0, 1],
            [0, 2],
            [0, 3],
            [0, 4],
            [4, 1],
            [3, 1],
            [2, 1],
            [1, 1],
            [0, 1],
            [1, 2],
            [2, 2],
            [3, 2],
            [4, 2],
            [0, 1],
            [4, 3],
            [2, 1]
        ]
        
        let loop = try DefaultEventLoop(label: "codes.vapor.test.translating")
        
        let serializer = SimpleByteSerializer().stream(on: loop)
        let parser = SimpleByteParser().stream(on: loop)
        let emitter = EmitterStream<[[UInt8]]>()
        
        var offset = 0
        var closed = false
        
        emitter.stream(to: serializer).output(to: parser)
        
        parser.drain { upstream in
            upstream.request(count: .max)
        }.output { buffer in
            XCTAssertEqual(buffer, cases[offset])
            offset += 1
        }.finally {
            closed = true
            XCTAssertEqual(cases.count, offset)
        }
        
        var sent = 0
        var size = 1
        
        while cases.count > sent {
            let consume = min(cases.count - sent, size)
            
            let serialize = Array(cases[sent..<sent + consume])
            
            size += 1
            sent += consume
            
            emitter.emit(serialize)
        }
        
        emitter.close()
        
        XCTAssert(closed)
    }

    static let allTests = [
        ("testPipeline", testPipeline),
        ("testDelta", testDelta),
        ("testCloseChaining", testCloseChaining),
        ("testCloseChaining", testCloseChaining),
        ("testTranslatingStream", testTranslatingStream),
        ("testTranslatingStreamOverflow", testTranslatingStreamOverflow),
        ("testPushStream", testPushStream),
        ("testPushStream", testPushStream),
        ("testPushStream", testPushStream),
    ]
}


/// MARK: Utilities

fileprivate final class SimpleByteParser: ByteParser {
    var state: ByteParserState<SimpleByteParser>
    
    typealias Input = UnsafeBufferPointer<UInt8>
    typealias Output = [UInt8]
    typealias Partial = UInt8?
    
    init() {
        self.state = .init()
    }
    
    func parseBytes(from buffer: SimpleByteParser.Input, partial: SimpleByteParser.Partial?) throws -> ByteParserResult<SimpleByteParser> {
        if let partial = partial, let partialByte = partial {
            guard buffer.count >= 1 else {
                return .uncompleted(partialByte)
            }
            
            return .completed(consuming: 1, result: [partialByte, buffer[0]])
        } else {
            guard buffer.count >= 1 else {
                return .uncompleted(nil)
            }
            
            if buffer.count >= 2 {
                return .completed(consuming: 2, result: [buffer[0], buffer[1]])
            } else {
                return .uncompleted(buffer[0])
            }
        }
    }
}

fileprivate final class SimpleByteSerializer: ByteSerializer {
    var state: ByteSerializerState<SimpleByteSerializer>
    
    typealias SerializationState = Int
    typealias Input = [[UInt8]]
    typealias Output = UnsafeBufferPointer<UInt8>
    
    var serializing = [UInt8]()
    
    init() {
        state = .init()
    }
    
    func serialize(_ input: Input, state: Int?) throws -> ByteSerializerResult<SimpleByteSerializer> {
        var state = state ?? 0
        
        guard input.count > state else {
            struct SomeError: Error {}
            throw SomeError()
        }
        
        self.serializing = input[state]
        state = state + 1
        
        return serializing.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<UInt8>) in
            if input.count == state {
                return .complete(buffer)
            } else {
                return .incomplete(buffer, state: state)
            }
        }
    }
}

fileprivate enum ArrayChunkingStreamState<S> {
    case ready
    case insufficient(S)
    case excess(S)
}

public final class ArrayChunkingStream<T>: TranslatingStream {
    private var state: ArrayChunkingStreamState<[T]>
    public let size: Int

    public init(size: Int) {
        state = .ready
        self.size = size
    }

    public func translate(input: [T]) -> TranslatingStreamResult<[T]> {
        switch state {
        case .ready:
            return handle(input)
        case .insufficient(let remainder):
            let input = remainder + input
            return handle(input)
        case .excess(let input):
            return handle(input)
        }
    }

    private func handle(_ input: [T]) -> TranslatingStreamResult<[T]> {
        if input.count == size {
            state = .ready
            return .sufficient(input)
        } else if input.count > size {
            let output = [T](input[..<size])
            let remainder = [T](input[size...])
            state = .excess(remainder)
            return .excess(output)
        } else {
            state = .insufficient(input)
            return .insufficient
        }
    }
}

