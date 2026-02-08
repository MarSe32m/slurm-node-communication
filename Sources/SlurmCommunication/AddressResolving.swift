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

internal struct ResolveAddress {
    internal enum Family {
        case IPv4
        case IPv6
    }

    internal let ipString: String
    internal let address: sockaddr_storage
    internal let socklen: socklen_t
    internal let family: Family
}

internal func resolve(host: String, port: UInt16) -> [ResolveAddress] {
    var hints = addrinfo()
    hints.ai_flags = AI_ADDRCONFIG
    hints.ai_family = AF_UNSPEC
    #if canImport(Glibc)
    hints.ai_socktype = .init(SOCK_STREAM.rawValue)
    #else
    hints.ai_socktype = SOCK_STREAM
    #endif

    #if canImport(WinSDK)
    hints.ai_protocol = IPPROTO_TCP.rawValue
    #else
    hints.ai_protocol = .init(IPPROTO_TCP)
    #endif
    hints.ai_addrlen = 0
    hints.ai_addr = nil
    hints.ai_canonname = nil
    hints.ai_next = nil   

    var res: UnsafeMutablePointer<addrinfo>?
    let portString = String(port)

    let error = getaddrinfo(host, portString, &hints, &res)
    guard error == 0, let res else {
        fatalError("Failed to get addr info: \(error)")
    }
    defer { freeaddrinfo(res) }

    var result: [ResolveAddress] = []
    var p: UnsafeMutablePointer<addrinfo>? = res

    while let ai = p?.pointee {
        defer { p = ai.ai_next }

        guard let sa = ai.ai_addr else { continue }

        // Only accept AF_INET / AF_INET6; skip anything else safely.
        let fam: ResolveAddress.Family
        switch Int32(ai.ai_family) {
        case AF_INET:  fam = .IPv4
        case AF_INET6: fam = .IPv6
        default:       continue
        }

        // Convert to numeric IP string
        var hostBuffer: [CChar] = .init(repeating: 0, count: Int(NI_MAXHOST))

        #if canImport(WinSDK)
        let nameInfoError = getnameinfo(
            sa,
            socklen_t(ai.ai_addrlen),
            &hostBuffer,
            DWORD(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        #else
        let nameInfoError = getnameinfo(
            sa,
            socklen_t(ai.ai_addrlen),
            &hostBuffer,
            socklen_t(hostBuffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        #endif
        guard nameInfoError == 0 else { continue }
        let ipString = hostBuffer.withUnsafeBufferPointer { buffer in 
            buffer.withMemoryRebound(to: UInt8.self) { buffer in 
                String(decodingCString: buffer.baseAddress!, as: UTF8.self)
            }
        }

        // Copy the full sockaddr (v4 or v6) into sockaddr_storage (no truncation)
        var storage = sockaddr_storage()
        memcpy(&storage, sa, Int(ai.ai_addrlen))

        result.append(
            ResolveAddress(
                ipString: ipString,
                address: storage,
                socklen: socklen_t(ai.ai_addrlen),
                family: fam
            )
        )
    }

    return result//.sorted { $0.family == .IPv4 && $1.family == .IPv6 }
}
