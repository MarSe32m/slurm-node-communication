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
internal let _accept: @convention(c) (_ socket: SOCKET, _ address: UnsafeMutablePointer<sockaddr>?, _ addressLength: UnsafeMutablePointer<socklen_t>?) -> SOCKET = WinSDK.accept
internal let _close: @convention(c) (_ socket: SOCKET) -> Int32 = closesocket
internal let _send: @convention(c) (_ socket: SOCKET, _ buffer: UnsafeRawPointer?, _ bufferSize: Int, _ flags: Int32) -> Int = send
internal let _recv: @convention(c) (_ socket: SOCKET, _ buffer: UnsafeMutableRawPointer?, _ bufferSize: Int, _ flags: Int32) -> Int = recv
#endif

public final class Server: Sendable {
    internal let socket: Int32
    public let totalWorkers: Int

    internal init(socket: Int32, totalWorkers: Int) {
        self.socket = socket
        self.totalWorkers = totalWorkers
    }

    public func accept() -> Client? {
        let newSocket = _accept(socket, nil, nil)
        if newSocket < 0 { return nil }
        return Client(socket: newSocket)
    }

    public func close() {
        let _ = _close(socket)
    }
}

public final class Client: Sendable {
    @usableFromInline
    internal let socket: Int32

    internal init(socket: Int32) {
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
            _send(socket, buffer.baseAddress, buffer.count, 0)
        }
    }
    
    public func receive(into buffer: inout [UInt8], fillBuffer: Bool = false) -> Int {
        _recv(socket, &buffer, buffer.count, fillBuffer ? .init(MSG_WAITALL) : 0)
    }

    //TODO: Is this correct?
    public func receive(into buffer: inout OutputRawSpan, fillBuffer: Bool = false) -> Int {
        buffer.withUnsafeMutableBytes { (buf, initilizedCapacity) in 
            let bytesReceived = _recv(socket, buf.baseAddress, buf.count - initilizedCapacity, fillBuffer ? .init(MSG_WAITALL) : 0)
            if bytesReceived < 0 { return bytesReceived }
            initilizedCapacity += bytesReceived
            return bytesReceived
        }
    }

    public func receive(into buffer: inout MutableRawSpan, fillBuffer: Bool = false) -> Int {
        buffer.withUnsafeMutableBytes { buffer in 
            _recv(socket, buffer.baseAddress, buffer.count, fillBuffer ? .init(MSG_WAITALL) : 0)
        }
    }

    public func close() {
        let _ = _close(socket)
    }
}

internal func setBlocking(_ fd: Int32, blocking: Bool) throws {
    if fd < 0 { 
        //TODO: Throw something
        return
    }
    #if os(Windows)
    let mode: UInt32 = blocking ? 0 : 1
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