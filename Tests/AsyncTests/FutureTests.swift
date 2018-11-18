import Async
import Dispatch
import XCTest

final class FutureTests : XCTestCase {
    func testSimpleFuture() throws {
        let promise = Promise(String.self)
        promise.complete("test")
        XCTAssertEqual(try promise.future.blockingAwait(), "test")
    }
    
    func testFutureThen() throws {
        let promise = Promise(String.self)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            promise.complete("test")
        }

        let group = DispatchGroup()
        group.enter()

        promise.future.do { result in
            XCTAssertEqual(result, "test")
            group.leave()
        }.catch { error in
            XCTFail("\(error)")
        }
        
        group.wait()
        XCTAssert(promise.future.isCompleted)
    }
    
    func testTimeoutFuture() throws {
        let promise = Promise(String.self)

        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            promise.complete("test")
        }
        
        XCTAssertFalse(promise.future.isCompleted)
        XCTAssertThrowsError(try promise.future.blockingAwait(timeout: .seconds(1)))
    }
    
    func testErrorFuture() throws {
        let promise = Promise(String.self)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            promise.fail(CustomError())
        }

        var executed = 0
        var caught = false

        let group = DispatchGroup()
        group.enter()
        promise.future.do { _ in
            XCTFail()
            executed += 1
        }.catch { error in
            executed += 1
            caught = true
            group.leave()
            XCTAssert(error is CustomError)
        }
        
        group.wait()
        XCTAssert(caught)
        XCTAssertTrue(promise.future.isCompleted)
        XCTAssertEqual(executed, 1)
    }

    func testArrayFuture() throws {
        let promiseA = Promise(String.self)
        let promiseB = Promise(String.self)

        let futures = [promiseA.future, promiseB.future]

        let group = DispatchGroup()
        group.enter()
        futures.flatten().do { array in
            XCTAssertEqual(array, ["a", "b"])
            group.leave()
        }.catch { error in
            XCTFail("\(error)")
        }

        promiseA.complete("a")
        promiseB.complete("b")

        group.wait()
    }

    func testFutureMap() throws {
        let intPromise = Promise(Int.self)

        let group = DispatchGroup()
        group.enter()

        intPromise.future.map (to: String.self){ int in
            return String(int)
        }.do { string in
            XCTAssertEqual(string, "42")
            group.leave()
        }.catch { error in
            XCTFail("\(error)")
            group.leave()
        }

        intPromise.complete(42)
        group.wait()
    }
    
    func testAlways() {
        var always = false
        
        Future<Void>(error: CustomError()).always {
            always = true
        }
        
        XCTAssert(always)
        
        always = false
        
        Future<Void>(()).always {
            always = true
        }
        
        XCTAssert(always)
    }
    
    func testFutureClosureInit() throws {
        let future = Future("hello")
        
        let otherFuture = Future<String>.flatMap {
            return future
        }
        
        try XCTAssertEqual(otherFuture.blockingAwait(), "hello")
    }
    
    func testDone() throws {
        XCTAssert(Future<Void>.done.isCompleted)
        XCTAssertNoThrow(try Future<Void>.done.blockingAwait())
        
        let signal = Promise<Void>()
        
        let signals: [Future<Void>] = [
            .done,
            .done,
            .done,
            .done,
            signal.future
        ]
        
        let groupedSignal = signals.flatten()
        
        XCTAssert(!groupedSignal.isCompleted)
        
        signal.complete()
        
        XCTAssert(signal.future.isCompleted)
        XCTAssert(groupedSignal.isCompleted)
        
        let completed = signals.transform {
            return Future("hello")
        }
        
        XCTAssert(completed.isCompleted)
        XCTAssertEqual(try completed.blockingAwait(), "hello")
    }
    
    func testFutureFlatMap() throws {
        let string = Promise<String>()
        let bool = Promise<Bool>()
        
        let integer = string.future.flatMap(to: Int?.self) { string in
            return bool.future.map (to: Int?.self){ bool in
                return bool ? Int(string) : -1
            }
        }
        
        string.complete("30")
        bool.complete(true)
        
        let int = try integer.blockingAwait()
        
        XCTAssertEqual(int, 30)
    }
    
    func testFutureFlatMap2() throws {
        let string = Promise<String>()
        let bool = Promise<Bool>()
        
        let integer = string.future.flatMap(to: Int?.self) { string in
            return bool.future.map(to: Int?.self) { bool in
                return bool ? Int(string) : -1
            }
        }
        
        string.complete("30")
        bool.complete(false)
        
        let int = try integer.blockingAwait()
        
        XCTAssertEqual(int, -1)
    }
    
    func testFutureFlatMapErrors() throws {
        let string = Promise<String>()
        let bool = Promise<Bool>()
        
        let integer = string.future.flatMap(to: Int?.self) { string in
            return bool.future.map(to: Int?.self) { bool in
                guard bool else {
                    throw CustomError()
                }
                
                return bool ? Int(string) : -1
            }
        }
        
        string.complete("30")
        bool.complete(false)
        
        XCTAssertThrowsError(try integer.blockingAwait())
    }
    
    func testSimpleMap() throws {
        let future = Future<Void>(())
        XCTAssertEqual(try future.transform(to: 3).blockingAwait(), 3)
    }
    
    func testCoalescing() throws {
        let future = Future<Int?>(nil)
        XCTAssertEqual(try (future ?? 4).blockingAwait(), 4)
        
        let future2 = Future<Int?>(5)
        XCTAssertEqual(try (future2 ?? 4).blockingAwait(), 5)
    }
    
    func testFutureFlatMapErrors2() throws {
        let string = Promise<String>()
        let bool = Promise<Bool>()
        
        let integer = string.future.flatMap(to: Int?.self) { string in
            guard string == "-1" else {
                throw CustomError()
            }
            
            return bool.future.map(to: Int?.self) { bool in
                return bool ? Int(string) : -1
            }
        }
        
        string.complete("30")
        bool.complete(false)
        
        XCTAssertThrowsError(try integer.blockingAwait())
    }
    
    func testPrecompleted() throws {
        let future = Future("Hello world")
        XCTAssertEqual(try future.blockingAwait(), "Hello world")
        
        let future2 = Future<Any>(error: CustomError())
        XCTAssertThrowsError(try future2.blockingAwait())
    }
    
    func testArrayFlatten() throws {
        var promises = [Promise<Int>]()
        let n = 100
        
        for _ in 0..<n {
            promises.append(Promise<Int>())
        }
        
        let futures = promises.map { $0.future }
        
        for i in 0..<promises.count - 1 {
            promises[i].complete(i)
        }
        
        let future = futures.flatten()
        
        XCTAssertFalse(future.isCompleted)
        
        promises.last?.complete(promises.count - 1)
        
        XCTAssert(future.isCompleted)
        
        let results = try future.blockingAwait()
        
        for (lhs, rhs) in results.enumerated() {
            XCTAssertEqual(lhs, rhs)
        }
    }
    
    func testArraySyncFlatten() throws {
        var lazyFutures = [LazyFuture<Int>]()
        let n = 10
        
        var completedOrder = [Int]()
        let completionQueue = DispatchQueue(label: "testArraySyncFlattenQueue")
        
        for i in 0..<n {
            lazyFutures.append({
                let promise = Promise<Int>()
                // delay promises so that each promise completes faster than the one before it
                let delay = TimeInterval(Double((n - i)) / 100)
                completionQueue.asyncAfter(deadline: .now() + delay) {
                    promise.complete(i)
                    completedOrder.append(i)
                }
                return promise.future
            })
        }
        
        let future = lazyFutures.syncFlatten()
        
        XCTAssertFalse(future.isCompleted)
        
        let results = try future.blockingAwait()
        
        XCTAssertTrue(future.isCompleted)
        
        XCTAssertTrue(results.count == n)
        
        for (lhs, rhs) in results.enumerated() {
            XCTAssertEqual(lhs, rhs)
        }
        
        XCTAssertEqual(completedOrder, results)
    }
    
    func testFlatMap() throws {
        let hello = Future("Hello")
        let world = Future("World")
        let smiley = Future(":)")
        
        let future0 = flatMap(to: String.self, hello, world) { a, b in
            return Future("\(a), \(b)!")
        }
        
        let future1 = flatMap(to: String.self, hello, world, smiley) { a, b, c in
            return Future("\(a), \(b)! \(c)")
        }
        
        XCTAssertEqual(try future0.blockingAwait(), "Hello, World!")
        XCTAssertEqual(try future1.blockingAwait(), "Hello, World! :)")
    }

    static let allTests = [
        ("testSimpleFuture", testSimpleFuture),
        ("testFutureThen", testFutureThen),
        ("testTimeoutFuture", testTimeoutFuture),
        ("testErrorFuture", testErrorFuture),
        ("testArrayFuture", testArrayFuture),
        ("testFutureMap", testFutureMap),
        ("testFutureFlatMap", testFutureFlatMap),
        ("testFutureFlatMap2", testFutureFlatMap2),
        ("testAlways", testAlways),
        ("testFutureClosureInit", testFutureClosureInit),
        ("testArrayFlatten", testArrayFlatten),
        ("testDone", testDone),
        ("testArrayFlatten", testArrayFlatten),
        ("testFutureFlatMapErrors", testFutureFlatMapErrors),
        ("testSimpleMap", testSimpleMap),
        ("testCoalescing", testCoalescing),
        ("testFutureFlatMapErrors2", testFutureFlatMapErrors2),
        ("testPrecompleted", testPrecompleted),
    ]
}

struct CustomError : Error {}
