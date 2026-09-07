import Foundation
import Testing

@testable import MoshDeckCore

struct DiagnosticsTests {
    @Test func underlyingServerTextNeverEntersExportedFailure() {
        let untrusted = "SYNTHETIC_PRIVATE_PROMPT_DO_NOT_EXPORT"
        let error = NSError(
            domain: untrusted, code: 42,
            userInfo: [NSLocalizedDescriptionKey: untrusted, NSDebugDescriptionErrorKey: untrusted])
        let failure = ConnectionFailure.capture(error, stage: .openingTransport)
        var lifecycle = ConnectionLifecycle()
        let id = lifecycle.begin()
        lifecycle.fail(id, failure)
        lifecycle.closed(id)
        #expect(!failure.message.contains(untrusted))
        #expect(!lifecycle.diagnostics.contains(untrusted))
        #expect(lifecycle.diagnostics.contains("42"))
        #expect(lifecycle.firstFailure == failure)
    }

    @Test func diagnosticHistoryIsBounded() {
        var lifecycle = ConnectionLifecycle()
        _ = lifecycle.begin()
        for index in 0..<150 { lifecycle.note("fixture stage index=\(index)") }
        #expect(lifecycle.timeline.count == 100)
        #expect(lifecycle.timeline.last?.contains("index=149") == true)
    }
}
