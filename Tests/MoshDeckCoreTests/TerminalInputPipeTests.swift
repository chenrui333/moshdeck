import Foundation
import Testing

@testable import MoshDeckCore

private actor InputSink {
    private var writes: [Data] = []
    private var release: CheckedContinuation<Void, Never>?
    private var arrivals: [CheckedContinuation<Void, Never>] = []

    func send(_ data: Data, suspend: Bool = false) async {
        writes.append(data)
        for arrival in arrivals { arrival.resume() }
        arrivals.removeAll()
        if suspend { await withCheckedContinuation { release = $0 } }
    }
    func waitForWrite() async {
        if !writes.isEmpty { return }
        await withCheckedContinuation { arrivals.append($0) }
    }
    func resume() {
        release?.resume()
        release = nil
    }
    func values() -> [Data] { writes }
}

struct TerminalInputPipeTests {
    @Test func stoppedAttemptCannotReplayQueuedOrOfflineInput() async throws {
        let old = InputSink()
        let replacement = InputSink()
        let pipe = TerminalInputPipe(failed: { Issue.record("Unexpected input failure") })
        pipe.bind { await old.send($0, suspend: true) }
        let first = Data("already handed to old transport".utf8)
        pipe.enqueue(first)
        await old.waitForWrite()
        pipe.enqueue(Data("pending before disconnection".utf8))
        pipe.stop()
        pipe.enqueue(Data("typed while reconnecting".utf8))
        // A stale callback cannot rebind an old pipe to a new transport.
        pipe.bind { await replacement.send($0) }
        await old.resume()
        let fresh = TerminalInputPipe(failed: { Issue.record("Unexpected input failure") })
        fresh.bind { await replacement.send($0) }
        let deliberate = Data("explicit new input after reconnect".utf8)
        fresh.enqueue(deliberate)
        await replacement.waitForWrite()
        await pipe.waitForDrain()
        await fresh.waitForDrain()
        #expect(await old.values() == [first])
        #expect(await replacement.values() == [deliberate])
        fresh.stop()
    }

    @Test func cancelledStartupDropsPendingProtocolReplies() async {
        let sink = InputSink()
        let pipe = TerminalInputPipe(failed: {})
        // The hidden startup renderer may generate terminal protocol replies
        // before channel binding; cancellation must discard them as well.
        pipe.enqueue(Data([27, 91, 48, 110]))
        pipe.stop()
        pipe.bind { await sink.send($0) }
        await pipe.waitForDrain()
        #expect(await sink.values().isEmpty)
    }

    @Test func overflowClosesThePipeInsteadOfDeliveringPartialQueuedInput() async {
        let sink = InputSink()
        let pipe = TerminalInputPipe(failed: {})
        pipe.enqueue(Data(repeating: 65, count: 128 * 1024))
        pipe.enqueue(Data([66]))
        pipe.bind { await sink.send($0) }
        await pipe.waitForDrain()
        #expect(await sink.values().isEmpty)
    }
}
