import Foundation
import Subprocess

internal func _getIDAndNodes() async -> (id: Int, nodes: [String]) {
    let env = ProcessInfo.processInfo.environment
    guard let procStr = env["SLURM_PROCID"],
            let proc = Int(procStr) else {
        return (0, ["localhost"])
    }
    let result = try? await Subprocess.run(
        .name("scontrol"),
        arguments: ["show", "hostnames"],
        output: .string(limit: 16 * 1024)
    )
    guard let nodes = result?.standardOutput?
    .split(whereSeparator: \.isNewline)
    .map(String.init) else {
        return (0, ["localhost"])
    }
    return (proc, nodes)
}

internal final class ThreadExecutor: TaskExecutor {
    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        Thread.detachNewThread {
            job.runSynchronously(on: self.asUnownedTaskExecutor())
        }
    }
}

/// Run work for the server node and worker nodes. 
/// - Parameters:
///   - serverFunction: Function that will run for the server node
///   - workerFunction: Function that will run for the worker nodes
public func withServerClient(serverFunction: @Sendable @escaping (sending Server) async -> Void, workerFunction: @Sendable @escaping (Client) async -> Void) async {
    let env = ProcessInfo.processInfo.environment
    let portString = env["HPC_MANAGEMENT_PORT"] ?? "25566"
    let port = UInt16(portString) ?? 25566
    let (id, nodes) = await _getIDAndNodes()

    let resolvedAddresses = nodes.map { resolve(host: $0, port: port) }
    print(resolvedAddresses)
    let isServer = (id == 0)
    let serverAddress = resolvedAddresses[0][0]
    let executor = ThreadExecutor()
    await withTaskExecutorPreference(executor) {
        await withDiscardingTaskGroup { group in 
            if isServer {
                group.addTask {
                    #if canImport(Glibc)
                    let listenSocket = socket(AF_INET6, .init(SOCK_STREAM.rawValue), 0)
                    #else
                    let listenSocket = socket(AF_INET6, SOCK_STREAM, 0)
                    #endif
                    var yes: Int32 = 1
                    setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
                    var v6Only: Int32 = 0
                    if setsockopt(listenSocket, .init(IPPROTO_IPV6), IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout.size(ofValue: v6Only))) != 0 {
                        print("Failed to set ipv6_v6only")
                    }
                    var localAddress = sockaddr_in6()
                    localAddress.sin6_family = .init(AF_INET6)
                    localAddress.sin6_addr = in6addr_any
                    localAddress.sin6_port = port.bigEndian // htons(port)
                    let bindResult = withUnsafePointer(to: localAddress) { addressPointer in 
                        addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in 
                            bind(listenSocket, addr, socklen_t(MemoryLayout.size(ofValue: localAddress)))
                        }
                    }
                    if bindResult < 0 { 
                        print(bindResult, errno)
                        fatalError("Failed to bind server") 
                    }
                    if listen(listenSocket, 256) != 0 { fatalError("Failed to listen on server socket") }
                    print("Listening !")
                    let server = Server(socket: listenSocket, totalWorkers: nodes.count)
                    await serverFunction(server)
                    
                }
            }
            group.addTask {
                #if canImport(Glibc)
                let socket = socket(serverAddress.family == .IPv4 ? AF_INET : AF_INET6, .init(SOCK_STREAM.rawValue), 0)
                #else
                let socket = socket(serverAddress.family == .IPv4 ? AF_INET : AF_INET6, SOCK_STREAM, 0)
                #endif
                if serverAddress.family == .IPv6 {
                    var v6Only: Int32 = 0
                    if setsockopt(socket, .init(IPPROTO_IPV6), IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout.size(ofValue: v6Only))) != 0 {
                        print("Failed to set ipv6_v6only")
                    }
                    var localAddress = sockaddr_in6()
                    localAddress.sin6_family = .init(AF_INET6)
                    localAddress.sin6_addr = in6addr_any
                    localAddress.sin6_port = 0 // htons(port)
                    let bindResult = withUnsafePointer(to: localAddress) { addressPointer in 
                        addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in 
                            bind(socket, addr, socklen_t(MemoryLayout.size(ofValue: localAddress)))
                        }
                    }
                    if bindResult < 0 { 
                        print(errno)
                        fatalError("Failed to bind worker") 
                    }
                } else {
                    var localAddress = sockaddr_in()
                    localAddress.sin_family = .init(AF_INET)
                    localAddress.sin_addr = .init(s_addr: INADDR_ANY)
                    localAddress.sin_port = 0 // htons(port)
                    let bindResult = withUnsafePointer(to: localAddress) { addressPointer in 
                        addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in 
                            bind(socket, addr, socklen_t(MemoryLayout.size(ofValue: localAddress)))
                        }
                    }
                    if bindResult < 0 { 
                        print(errno)
                        fatalError("Failed to bind worker") 
                    }
                }
                
                let connectionStart = ContinuousClock.now
                var connected = false
                while .now - connectionStart < .seconds(120) && !connected {
                    let connectResult = withUnsafePointer(to: serverAddress.address) { addrPtr in 
                        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in 
                            connect(socket, address, serverAddress.socklen)
                        }
                    }
                    connected = connectResult == 0
                    try? await Task.sleep(for: .milliseconds(100))
                    print(connectResult, errno)
                }
                if !connected { fatalError("Failed to connect to server node") }
                let client = Client(socket: socket)
                await workerFunction(client)
            }
        }
    }
}