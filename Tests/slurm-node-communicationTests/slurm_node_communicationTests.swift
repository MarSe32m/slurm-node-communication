import Testing
import SlurmCommunication

@Test(.timeLimit(.minutes(1))) 
func example() async throws {
    await withServerClient(
        serverFunction: { server in 
            await withDiscardingTaskGroup { group in 
                var workersConnected = 0
                while workersConnected < server.totalWorkers, let newWorker = server.accept() {
                    group.addTask {
                        var buffer: [UInt8] = .init(repeating: 0, count: 1024)
                        let bytesReceived = newWorker.receive(into: &buffer, fillBuffer: true)
                        for i in buffer.indices {
                            #expect(UInt8(i % 256) == buffer[i])
                        }
                        #expect(bytesReceived == 1024)
                        let nullReceive = newWorker.receive(into: &buffer)
                        #expect(nullReceive == 0)
                    }
                    workersConnected += 1
                }
            }
            server.close()
        }, 
        workerFunction: { client in 
            var buffer: [UInt8] = .init(repeating: 0, count: 1024)
            for i in 0..<1024 {
                buffer[i] = UInt8(i % 256)
            }
            let bytesSent = client.send(data: buffer)
            #expect(bytesSent == 1024)
            client.close()
        }
    )
    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}
