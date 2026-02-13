import Synchronization

internal final class Semaphore: @unchecked Sendable {
    let lock: Mutex<Void> = Mutex(())
    var count: Int = 0
    // We don't need to care about the suboptimal performance of an array,
    // since wait will not be called concurrently anyway
    var waiters: [UnsafeContinuation<Void, Never>] = []

    init() {}

    func wait() async {
        lock._unsafeLock()
        count -= 1
        if count >= 0 {
            lock._unsafeUnlock()
            return
        }
        await withUnsafeContinuation {
            waiters.append($0)
            lock._unsafeUnlock()
        }
    }

    func signal() {
        lock.withLock { _ in 
            count += 1
            if waiters.isEmpty { return }
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}