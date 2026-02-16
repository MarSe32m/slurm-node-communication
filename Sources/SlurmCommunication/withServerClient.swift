import Foundation
import Subprocess
import Synchronization

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#elseif canImport(WinSDK)
import WinSDK
#else
#error("Unsupported platform")
#endif

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

internal func _getNumberOfTasks() -> Int {
    let env = ProcessInfo.processInfo.environment
    guard let nTasks = env["SLURM_NTASKS"],
          let numberOfTasks = Int(nTasks) else { return 1 }
    return numberOfTasks
}

/// Run work for the server node and worker nodes. 
/// - Parameters:
///   - serverFunction: Function that will run for the server node
///   - workerFunction: Function that will run for the worker nodes
public func withServerClient(serverFunction: @Sendable @escaping (sending Server) -> Void, workerFunction: @Sendable @escaping (Client) -> Void) async {
    let env = ProcessInfo.processInfo.environment
    let portString = env["HPC_MANAGEMENT_PORT"] ?? "25565"
    let port = UInt16(portString) ?? 25565
    let (id, nodes) = await _getIDAndNodes()
    let numberOfTasks = _getNumberOfTasks()
    let isServer = (id == 0)
    let serverAddress = resolve(host: isServer ? "127.0.0.1" : nodes[0], port: port)[0]
    let taskCount = isServer ? 2 : 1
    let semaphore = Semaphore()
    if isServer {
        Thread.detachNewThread {
            defer { semaphore.signal() }
            #if canImport(Glibc)
            let listenSocket = socket(serverAddress.family == .IPv4 ? AF_INET : AF_INET6, .init(SOCK_STREAM.rawValue), 0)
            #else
            let listenSocket = socket(serverAddress.family == .IPv4 ? AF_INET : AF_INET6, SOCK_STREAM, 0)
            #endif
            var yes: Int32 = 1
            setsockopt(listenSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
            if serverAddress.family == .IPv6 {
                var v6Only: Int32 = 0
                #if canImport(WinSDK)
                if setsockopt(listenSocket, .init(IPPROTO_IPV6.rawValue), IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout.size(ofValue: v6Only))) != 0 {
                    print("Failed to set ipv6_v6only")
                }
                #else
                if setsockopt(listenSocket, .init(IPPROTO_IPV6), IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout.size(ofValue: v6Only))) != 0 {
                    print("Failed to set ipv6_v6only")
                }
                #endif
            }
            if serverAddress.family == .IPv4 {
                var localAddress = sockaddr_in()
                localAddress.sin_family = .init(AF_INET)
                #if canImport(WinSDK)
                localAddress.sin_addr.S_un.S_addr = INADDR_ANY
                #else
                localAddress.sin_addr.s_addr = INADDR_ANY
                #endif
                localAddress.sin_port = port.bigEndian // htons(port)
                let bindResult = withUnsafePointer(to: localAddress) { addressPointer in 
                    addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { addr in 
                        bind(listenSocket, addr, socklen_t(MemoryLayout.size(ofValue: localAddress)))
                    }
                }
                if bindResult < 0 { 
                    print(bindResult, errno)
                    fatalError("Failed to bind server") 
                }
            } else {
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
            }
            
            if listen(listenSocket, .init(numberOfTasks)) != 0 { fatalError("Failed to listen on server socket") }
            let server = Server(socket: listenSocket, totalWorkers: numberOfTasks)
            serverFunction(server)
        }
    }
    print("Starting client thread")
    Thread.detachNewThread {
        if isServer {
            print("Server worker starting to connect!")
        }
        defer { semaphore.signal() }
        #if canImport(Glibc)
        let socket = socket(serverAddress.family == .IPv4 ? AF_INET : AF_INET6, .init(SOCK_STREAM.rawValue), 0)
        #else
        let socket = socket(serverAddress.family == .IPv4 ? AF_INET : AF_INET6, SOCK_STREAM, 0)
        #endif
        if serverAddress.family == .IPv6 {
            var v6Only: Int32 = 0
            #if canImport(WinSDK)
            if setsockopt(socket, .init(IPPROTO_IPV6.rawValue), IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout.size(ofValue: v6Only))) != 0 {
                print("Failed to set ipv6_v6only")
            }
            #else
            if setsockopt(socket, .init(IPPROTO_IPV6), IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout.size(ofValue: v6Only))) != 0 {
                print("Failed to set ipv6_v6only")
            }
            #endif
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
            #if canImport(WinSDK)
            localAddress.sin_addr.S_un.S_addr = INADDR_ANY
            #else
            localAddress.sin_addr = .init(s_addr: INADDR_ANY)
            #endif
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
            if connected { break }
            Thread.sleep(forTimeInterval: 0.1)
            if isServer {
                print("Connecting...")
            }
        }
        if !connected { fatalError("Failed to connect to server node") }
        if isServer {
            print("Connected from server worker!")
        }
        let client = Client(socket: socket, id: id, sendId: true)
        workerFunction(client)
    }

    for _ in 0..<taskCount { await semaphore.wait() }
}