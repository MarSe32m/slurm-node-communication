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

#if os(Linux) || canImport(Darwin)
@usableFromInline
internal let _accept: @convention(c) (_ socket: Int32, _ address: UnsafeMutablePointer<sockaddr>?, _ addressLength: UnsafeMutablePointer<socklen_t>?) -> Int32 = accept
internal let _close: @convention(c) (_ socket: Int32) -> Int32 = close
internal let _send: @convention(c) (_ socket: Int32, _ buffer: UnsafeRawPointer?, _ bufferSize: Int, _ flags: Int32) -> Int = send
internal let _recv: @convention(c) (_ socket: Int32, _ buffer: UnsafeMutableRawPointer?, _ bufferSize: Int, _ flags: Int32) -> Int = recv
#elseif os(Windows)
internal let _accept: @convention(c) (_ socket: SOCKET, _ address: UnsafeMutablePointer<sockaddr>?, _ addressLength: UnsafeMutablePointer<socklen_t>?) -> SOCKET = accept
internal let _close: @convention(c) (_ socket: SOCKET) -> Int32 = closesocket
internal let _send: @convention(c) (_ socket: SOCKET, _ buffer: UnsafePointer<CChar>?, _ bufferSize: Int32, _ flags: Int32) -> Int32 = send
internal let _recv: @convention(c) (_ socket: SOCKET, _ buffer: UnsafeMutablePointer<CChar>?, _ bufferSize: Int32, _ flags: Int32) -> Int32 = recv
#endif

#if canImport(WinSDK)
@usableFromInline
internal typealias SocketHandle = SOCKET
#else
@usableFromInline
internal typealias SocketHandle = Int32
#endif

public final class Server: Sendable {
    internal let socket: SocketHandle
    public let totalWorkers: Int

    internal init(socket: SocketHandle, totalWorkers: Int) {
        self.socket = socket
        self.totalWorkers = totalWorkers
    }

    public func accept() -> Client? {
        let newSocket = _accept(socket, nil, nil)
        #if canImport(WinSDK)
        if newSocket == INVALID_SOCKET { return nil }
        #else
        if newSocket < 0 { return nil }
        #endif
        return Client(socket: newSocket)
    }

    public func close() {
        let _ = _close(socket)
    }
}

public final class Client: Sendable {
    @usableFromInline
    internal let socket: SocketHandle

    internal init(socket: SocketHandle) {
        self.socket = socket
    }

    public func setNonblocking(_ blocking: Bool = true) throws {
        try setBlocking(socket, blocking: blocking)
    }

    public func send(data buffer: [UInt8]) -> Int {
        send(data: buffer.span.bytes)
    }

    public func send(data buffer: borrowing RawSpan) -> Int {
        buffer.withUnsafeBytes { buffer in 
            #if canImport(WinSDK)
            buffer.withMemoryRebound(to: CChar.self) { buffer in 
                Int(_send(socket, buffer.baseAddress, Int32(buffer.count), 0))
            }
            #else
            _send(socket, buffer.baseAddress, buffer.count, 0)
            #endif
        }
    }
    
    public func receive(into buffer: inout [UInt8], fillBuffer: Bool = false) -> Int {
        #if canImport(WinSDK)
        buffer.withUnsafeMutableBytes { buffer in 
            buffer.withMemoryRebound(to: CChar.self) { buffer in 
                Int(_recv(socket, buffer.baseAddress, Int32(buffer.count), 0))
            }
        }
        #else
        _recv(socket, &buffer, buffer.count, fillBuffer ? .init(MSG_WAITALL) : 0)
        #endif
    }

    //TODO: Is this correct?
    public func receive(into buffer: inout OutputRawSpan, fillBuffer: Bool = false) -> Int {
        buffer.withUnsafeMutableBytes { (buf, initilizedCapacity) in 
            #if canImport(WinSDK)
            let bytesReceived = buf.withMemoryRebound(to: CChar.self) { buffer in 
                Int(_recv(socket, buffer.baseAddress, Int32(buffer.count - initilizedCapacity), fillBuffer ? .init(MSG_WAITALL) : 0))
            }
            #else
            let bytesReceived = _recv(socket, buf.baseAddress, buf.count - initilizedCapacity, fillBuffer ? .init(MSG_WAITALL) : 0)
            #endif
            if bytesReceived < 0 { return bytesReceived }
            initilizedCapacity += bytesReceived
            return bytesReceived
        }
    }

    public func receive(into buffer: inout MutableRawSpan, fillBuffer: Bool = false) -> Int {
        buffer.withUnsafeMutableBytes { buffer in 
            #if canImport(WinSDK)
            buffer.withMemoryRebound(to: CChar.self) { buffer in 
                Int(_recv(socket, buffer.baseAddress, Int32(buffer.count), fillBuffer ? .init(MSG_WAITALL) : 0))
            }
            #else
            _recv(socket, buffer.baseAddress, buffer.count, fillBuffer ? .init(MSG_WAITALL) : 0)
            #endif
        }
    }

    public func close() {
        let _ = _close(socket)
    }
}

internal func setBlocking(_ fd: SocketHandle, blocking: Bool) throws {
    #if canImport(WinSDK)
    if fd == INVALID_SOCKET {
        //TODO: Throw something
        return
    }
    #else
    if fd < 0 { 
        //TODO: Throw something
        return
    }
    #endif
    #if os(Windows)
    var mode: UInt32 = blocking ? 0 : 1
    if ioctlsocket(fd, FIONBIO, &mode) != 0 {
        //TODO: Throw something
    }
    #else
    var flags = fcntl(fd, F_GETFL)
    if flags == -1 {
        //TODO: Throw something
        return
    }
    flags = blocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK)
    if fcntl(fd, F_SETFL, flags) != 0 {
        //TODO: Throw something
    }
    #endif
}