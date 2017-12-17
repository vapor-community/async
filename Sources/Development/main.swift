import Async
import Foundation

func test<EventLoop>(_ type: EventLoop.Type) throws
    where EventLoop: Async.EventLoop
{
    print("Testing: \(EventLoop.self)")
    // let eventLoop = DispatchEventLoop()
    let accept = try EventLoop(label: "Accept Worker")

    var loopOffset: Int = 0
    var loops: [EventLoop] = []
    for i in 0..<8 {
        try loops.append(.init(label: "Worker \(i)"))
    }

    for loop in loops {
        if #available(OSX 10.12, *) {
            Thread.detachNewThread {
                loop.run()
            }
        } else {
            fatalError()
        }
    }

    let tcpSocket = try TCPSocket(isNonBlocking: true, shouldReuseAddress: false)
    let tcpServer = try TCPServer(socket: tcpSocket)
    try tcpServer.start(hostname: "localhost", port: 8123, backlog: 128)
    let acceptStream = tcpServer.stream(on: accept)

    var response = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n".utf8)

    acceptStream.drain { upstream in
        upstream.request(count: .max)
        }.output { client in
            loopOffset += 1
            if loopOffset >= loops.count {
                loopOffset = 0
            }
            let stream = client.stream(on: loops[loopOffset])
            var upstream: ConnectionContext?
            stream.drain { context in
                upstream = context
                context.request(count: 1)
                }
                .output { buffer in
                    //                stream.next(buffer)
                    response.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                        let buffer = UnsafeBufferPointer<UInt8>(start: bytes, count: response.count)
                        stream.next(buffer)
                    }
                    upstream?.request(count: 1)
                }.catch { error in
                    print("\(error)")
                }.finally {
                    print("CLOSED")
            }
        }.catch { error in
            print("\(error)")
        }.finally {
            print("CLOSED")
    }

    accept.run()
}

do {
    try test(KqueueEventLoop.self)
    // try test(DispatchEventLoop.self)
}
