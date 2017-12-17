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

    let tcpSocket = try TCPSocket(isNonBlocking: true, shouldReuseAddress: true)
    let tcpServer = try TCPServer(socket: tcpSocket)
    try tcpServer.start(hostname: "localhost", port: 8123, backlog: 128)
    let acceptStream = tcpServer.stream(on: accept)

    let message = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    var response = Data("HTTP/1.1 200 OK\r\nContent-Length: \(message.count)\r\n\r\n\(message)".utf8)
    let responseBuffer = response.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
        return UnsafeBufferPointer<UInt8>(start: bytes, count: response.count)
    }

    acceptStream.drain { upstream in
        upstream.request(count: .max)
    }.output { client in
        // print(client)
        loopOffset += 1
        if loopOffset >= loops.count {
            loopOffset = 0
        }
        let source = client.socket.source(on: loops[loopOffset])
        let sink = client.socket.sink(on: loops[loopOffset])
        source.map(to: ByteBuffer.self) { buffer in
            // print(String(bytes: buffer, encoding: .utf8)!)
            return responseBuffer
        }.output(to: sink)
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
