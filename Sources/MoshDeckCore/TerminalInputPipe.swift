import Foundation

/// Callbacks enter synchronously from Ghostty. A locked FIFO preserves their
/// arrival order, and one worker awaits each SSH write. No per-byte Task race.
public final class TerminalInputPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [Data] = []
    private var queuedBytes = 0
    public typealias Sender = @Sendable (Data) async throws -> Void
    private var sender: Sender?
    private var active = true
    private var draining = false
    private var idleWaiters: [CheckedContinuation<Void, Never>] = []
    private let failed: @Sendable () -> Void

    public init(failed: @escaping @Sendable () -> Void) { self.failed = failed }

    public func bind(_ sender: @escaping Sender) {
        lock.lock()
        guard active, self.sender == nil else {
            lock.unlock()
            return
        }
        self.sender = sender
        let start = active && !draining && !queue.isEmpty
        if start { draining = true }
        lock.unlock()
        if start { startDrain() }
    }

    public func enqueue(_ data: Data) {
        lock.lock()
        guard active else {
            lock.unlock()
            return
        }
        guard queuedBytes + data.count <= 128 * 1024 else {
            active = false
            queue.removeAll()
            queuedBytes = 0
            lock.unlock()
            failed()
            return
        }
        queue.append(data)
        queuedBytes += data.count
        let start = sender != nil && !draining
        if start { draining = true }
        lock.unlock()
        if start { startDrain() }
    }

    public func stop() {
        lock.lock()
        active = false
        sender = nil
        queue.removeAll()
        queuedBytes = 0
        lock.unlock()
    }

    /// Wait for the current worker to finish. This is not remote execution
    /// acknowledgement; stopped or overflowed queued data is discarded.
    public func waitForDrain() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if draining {
                idleWaiters.append(continuation)
                lock.unlock()
            } else {
                lock.unlock()
                continuation.resume()
            }
        }
    }

    private func next() -> (Sender, Data)? {
        lock.lock()
        guard active, let sender, !queue.isEmpty else {
            draining = false
            let waiters = idleWaiters
            idleWaiters.removeAll()
            lock.unlock()
            for waiter in waiters { waiter.resume() }
            return nil
        }
        let bytes = queue.removeFirst()
        queuedBytes -= bytes.count
        lock.unlock()
        return (sender, bytes)
    }

    private func startDrain() {
        Task {
            while let (sender, bytes) = next() {
                do { try await sender(bytes) } catch {
                    stop()
                    failed()
                    // The next iteration releases all drain waiters.
                }
            }
        }
    }
}
