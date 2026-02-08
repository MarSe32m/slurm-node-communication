// The Swift Programming Language
// https://docs.swift.org/swift-book

import SlurmCommunication

@main
struct hpc_management {
    static func main() async throws {
        await withServerClient(serverFunction: { server in 
            await withDiscardingTaskGroup { group in 
                var workersConnected = 0
                while workersConnected < server.totalWorkers, let newClient = server.accept() {
                    group.addTask {
                        var buffer: [UInt8] = .init(repeating: 0, count: 1024)
                        while true {
                            let bytesReceived = newClient.receive(into: &buffer)
                            if bytesReceived <= 0 { break }
                            let bytesSent = newClient.send(data: buffer[0..<bytesReceived].span.bytes)
                            if bytesReceived != bytesSent {
                                print("Size mismatch")
                            }
                        }
                        newClient.close()
                        print("[Server]: Worker done")
                    }
                    workersConnected += 1
                }
            }
            print("[Server] Done!")
            server.close()
        }, workerFunction: { client in 
            let buffer: [UInt8] = (0..<1024).map { _ in .random(in: .min ... .max) }
            for iteration in 1...1_000_000 {
                if iteration % 100_000 == 0 {
                    print(iteration)
                }
                let bytesSent = client.send(data: buffer)
                var sendBuffer = Array(buffer[0..<bytesSent])
                let bytesReceived = client.receive(into: &sendBuffer, fillBuffer: true)
                if bytesSent != bytesReceived { print("Mismatch") }
            }
            client.close()
            print("Done!")
        })
    }
}
