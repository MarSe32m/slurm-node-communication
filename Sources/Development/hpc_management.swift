// The Swift Programming Language
// https://docs.swift.org/swift-book

import SlurmCommunication
import Dispatch
import Synchronization
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
                }
                print("[Server]: Client done!")
            }
            print("[Server]: Server done!")
        }, 
        workerFunction: { client in 
            print("Client:", client.id, "connected!")
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
        }
    )
}

func echoTest() async {
    await withServerClient(serverFunction: { server in 
        let clients = server.acceptAll()
        if clients.isEmpty {
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
            print("[Server]: Worker done")
            return bytesReceived
        }
        print("[Server] Done! Received bytes in total:", result.reduce(0, +))
    }, workerFunction: { client in 
        print("Client:", client.id, "connected!")
        let buffer: [UInt8] = .init(repeating: 0, count: 1024)
        for iteration in 1...1_000_00 {
            if iteration % 10_000 == 0 {
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
        print("Done!")
    })
}

@main
struct hpc_management {
    static func main() async throws {
        print("Work test")
        await workTest()
        print("Parameter test")
        await parameterSendingTest()
        print("Echo test")
        await echoTest()
    }
}

func serverFunc(_ server: Server) {
    let batchSize = ProcessInfo.processInfo.activeProcessorCount
    let parameters: [(Int, Int)] = {
        var _parameters: [(Int, Int)] = []
        for i in 0..<1000 {
            for j in 0..<1000 {
                _parameters.append((i, j))
            }
        }
        return _parameters
    }()
    let index: Atomic<Int> = Atomic(0)
    let clients = server.acceptAll()
    if clients.isEmpty { return }
    let result = clients.parallelMap { worker in 
        var parametersReceived = 0
        upperLoop: while true {
            var parametersSent = 0
            for _ in 0..<batchSize {
                let _index = index.add(1, ordering: .relaxed).oldValue
                if _index < parameters.count {
                    if (_index + 1) % 10_000 == 0 {
                        print(_index + 1, parameters.count)
                    }
                    let parameter = parameters[_index]
                    var data: [UInt8] = []
                    data.append(0)
                    withUnsafeBytes(of: parameter) { data.append(contentsOf: $0) }
                    if !worker.send(data: data) {
                        print("Failed to send params")
                        worker.close()
                        break upperLoop
                    }
                    parametersSent += 1
                } else {
                    let data: [UInt8] = [1]
                    if !worker.send(data: data) {
                        print("Failed to send final params")
                        worker.close()
                        break
                    }
                }
            }
            for _ in 0..<parametersSent {
                let response = worker.receive()
                if response.count != 11 {
                    break upperLoop
                }
                for i in 0..<11 {
                    precondition(response[i] == UInt8(i))
                }
                parametersReceived += 1
            }
            if parametersSent < batchSize { break }
        }
        return parametersReceived
    }
    let totalParametersReceived = result.reduce(0, +)
    print(parameters.count, totalParametersReceived)
}

func workerFunc(_ client: Client) {
    print("Client:", client.id, "connected!")
    let batchSize = ProcessInfo.processInfo.activeProcessorCount
    var parameters: [(Int, Int)] = []
    outerLoop: while true {
        parameters.removeAll(keepingCapacity: true)
        for _ in 0..<batchSize {
            let buffer = client.receive()
            if buffer.isEmpty { break }
            if buffer.count == 1 + MemoryLayout<(Int, Int)>.stride {
                if buffer[0] == 0 {
                    buffer.withUnsafeBytes { buffer in 
                        let parameter = buffer.loadUnaligned(fromByteOffset: 1, as: (Int, Int).self)
                        parameters.append(parameter)
                    }
                }
            } else {
                if buffer[0] != 1 {
                    print("Invalid termination packet")
                }
            }
        }
        let results = parameters.parallelMap { param in 
            for i in 0..<param.0 {
                for j in 0..<param.1 {
                    if i * j == 111111111 {
                        print(i, j)
                    }
                }
            }
            return param
        }
        if results.isEmpty { break }
        for _ in results {
            if !client.send(data: (0..<11).map { UInt8($0) }) {
                print("Couldnt send data to server")
                break outerLoop
            }
        }
    }
}

func workTest() async {
    await withServerClient(
        serverFunction: serverFunc, 
        workerFunction: workerFunc
    )
}