// The Swift Programming Language
// https://docs.swift.org/swift-book

import SlurmCommunication
import Dispatch
import Synchronization

extension Array {
    func parallelMap<T>(_ body: @Sendable (Element) -> T) -> [T] {
        nonisolated(unsafe) let copySelf = self
        return .init(unsafeUninitializedCapacity: count) { buffer, initializedCount in 
            nonisolated(unsafe) let buffer = buffer
            DispatchQueue.concurrentPerform(iterations: count) { i in 
                let newElement = body(copySelf[i])
                buffer.initializeElement(at: i, to: newElement)
            }
            initializedCount = count
        }
    }
}

func parameterSendingTest() async {
    await withServerClient(
        serverFunction: { server in
            let clients = server.acceptAll()
            if clients.isEmpty {
                server.close()
                return
            }
            let _ = clients.parallelMap { client in 
                for i in 0..<10000 {
                    let iBytes: [UInt8] = withUnsafeBytes(of: i) { Array($0) }
                    let buffer = [0] + iBytes 
                    if !client.send(data: buffer) {
                        print("[Server]: Failed to send")
                        return
                    }
                }
                for i in 0..<10000 {
                    let buffer = client.receive()
                    precondition(buffer.count == 1 + 8 + 3)
                    precondition(buffer[0] == 1)
                    let integer = buffer.withUnsafeBytes { bufferPointer in 
                        bufferPointer.loadUnaligned(fromByteOffset: 1, as: Int.self)
                    }
                    precondition(integer == i)
                    precondition(buffer[9] == 33)
                    precondition(buffer[10] == 44)
                    precondition(buffer[11] == 55)
                    print(i)
                }
                client.close()
                print("[Server]: Client done!")
            }
            print("[Server]: Server done!")
            server.close()
        }, 
        workerFunction: { client in 
            for i in 0..<10000 {
                let buffer = client.receive()
                precondition(buffer.count == 1 + 8)
                precondition(buffer[0] == 0)
                let integer = buffer.withUnsafeBytes { bufferPointer in 
                    bufferPointer.loadUnaligned(fromByteOffset: 1, as: Int.self)
                }
                precondition(integer == i)
                if !client.send(data: [1] + Array(buffer[1...]) + [33, 44, 55]) {
                    print("[Client]: Failed to send!")
                    break
                }
            }
            print("[Client]: Client done!")
            client.close()
        }
    )
}

func echoTest() async {
    await withServerClient(serverFunction: { server in 
        let clients = server.acceptAll()
        if clients.isEmpty {
            server.close()
            return
        }
        let result = clients.parallelMap { client in 
            var bytesReceived = 0
            while true {
                let buffer = client.receive()
                bytesReceived += buffer.count
                if buffer.isEmpty { break }
                let bytesSent = client.send(data: buffer)
                if !bytesSent { break }
            }
            client.close()
            print("[Server]: Worker done")
            return bytesReceived
        }
        print("[Server] Done! Received bytes in total:", result.reduce(0, +))
        server.close()
    }, workerFunction: { client in 
        let buffer: [UInt8] = .init(repeating: 0, count: 1024)
        for iteration in 1...1_000_00 {
            print(iteration)
            if iteration % 100_000 == 0 {
                print(iteration)
            }
            let bytesSent = client.send(data: buffer)
            if !bytesSent { break }
            let receivedBuffer = client.receive()
            if receivedBuffer != buffer { 
                print("Mismatch")
                break 
            }
        }
        client.close()
        print("Done!")
    })
}

@main
struct hpc_management {
    static func main() async throws {
        print("Parameter test")
        await parameterSendingTest()
        print("Echo test")
        await echoTest()
    }
}
