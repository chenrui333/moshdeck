import Foundation
import Testing

@testable import MoshDeckCore

struct SessionSwipeTests {
    @Test func displacementVelocityAndCancellation() {
        #expect(!SessionSwipe.isHorizontal(x: 5, y: 0))
        #expect(!SessionSwipe.isHorizontal(x: 40, y: 50))
        #expect(!SessionSwipe.commits(x: -25, y: 1, velocityX: -1500, width: 430))
        #expect(!SessionSwipe.commits(x: -70, y: 1, velocityX: 1200, width: 430))
        #expect(SessionSwipe.commits(x: -65, y: 1, velocityX: -1200, width: 430))
        #expect(SessionSwipe.commits(x: 150, y: 30, velocityX: 0, width: 430))
        #expect(!SessionSwipe.commits(x: 150, y: 130, velocityX: 1500, width: 430))
        #expect(!SessionSwipe.commits(x: 10, y: 0, velocityX: 0, width: 430))
    }

    @Test func pickerOrderAndNoWrap() throws {
        let sessions = try TmuxSessionListing.parse(Data("work|1|1\ninfra|1|0\nhomebrew|1|0\n".utf8))
        #expect(SessionSwipe.target(in: sessions, current: "infra", x: -100)?.name == "work")
        #expect(SessionSwipe.target(in: sessions, current: "infra", x: 100)?.name == "homebrew")
        #expect(SessionSwipe.target(in: sessions, current: "work", x: -100) == nil)
        #expect(SessionSwipe.target(in: sessions, current: "homebrew", x: 100) == nil)
        #expect(SessionSwipe.target(in: sessions, current: "unknown", x: 100) == nil)
    }

    @Test func metadataRejectsUnknownCurrentSessionAndUnsafeTargets() throws {
        #expect(throws: TmuxListingError.invalidResponse) {
            try TmuxClientSnapshot.parse(Data("missing\nwork|1|1\n".utf8))
        }
        #expect(throws: (any Error).self) {
            try TmuxClientCommand.switchSession(to: "work;touch nope", from: "work", executable: "tmux")
        }
        let snapshot = try TmuxClientSnapshot.parse(Data("work\nwork|1|1\n".utf8))
        #expect(snapshot.currentSession == "work")
    }
}
