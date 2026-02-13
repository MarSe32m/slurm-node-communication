import Testing
import SlurmCommunication
import Dispatch

extension Array where Element: Sendable {
    func parallelForEach(_ body: @Sendable (Element) -> Void) {
        DispatchQueue.concurrentPerform(iterations: count) { body(self[$0]) }
    }
}

@Test(.timeLimit(.minutes(1))) 
func basicUsage() async throws {
    await withServerClient(
        serverFunction: { server in 
            let clients = server.acceptAll()
            if clients.isEmpty {
                server.close()
                return
            }
            clients.parallelForEach { client in 
                let buffer = client.receive()
                for i in buffer.indices {
                    #expect(UInt8(i % 256) == buffer[i])
                }
                #expect(buffer.count == 1024)
                let nullReceive = client.receive()
                #expect(nullReceive.isEmpty)
            }
            server.close()
        }, 
        workerFunction: { client in 
            var buffer: [UInt8] = .init(repeating: 0, count: 1024)
            for i in 0..<1024 {
                buffer[i] = UInt8(i % 256)
            }
            let bytesSent = client.send(data: buffer)
            #expect(bytesSent)
            client.close()
        }
    )
}

@Test(.timeLimit(.minutes(2)))
func multiTypeMessage() async throws {
    await withServerClient(
        serverFunction: { server in
            let clients = server.acceptAll()
            if clients.isEmpty {
                server.close()
                return
            }
            clients.parallelForEach { client in 
                for i in 0..<10 {
                    let iBytes: [UInt8] = withUnsafeBytes(of: i) { Array($0) }
                    let buffer = [0] + iBytes 
                    #expect(client.send(data: buffer))
                }
                for i in 0..<10 {
                    let buffer = client.receive()
                    #expect(buffer.count == 1 + 8 + 3)
                    #expect(buffer[0] == 1)
                    let integer = buffer.withUnsafeBytes { bufferPointer in 
                        bufferPointer.loadUnaligned(fromByteOffset: 1, as: Int.self)
                    }
                    #expect(integer == i)
                    #expect(buffer[9] == 33)
                    #expect(buffer[10] == 44)
                    #expect(buffer[11] == 55)
                }
                client.close()
            }
            server.close()
        }, 
        workerFunction: { client in 
            for i in 0..<10 {
                let buffer = client.receive()
                #expect(buffer.count == 1 + 8)
                #expect(buffer[0] == 1)
                let integer = buffer.withUnsafeBytes { bufferPointer in 
                    bufferPointer.loadUnaligned(fromByteOffset: 1, as: Int.self)
                }
                #expect(integer == i)
                client.send(data: buffer + [33, 44, 55])
            }
            client.close()
        }
    )
}