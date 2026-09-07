import Foundation
import Testing

@testable import MoshDeckCore

struct AppLockPolicyTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test func foregroundSessionDoesNotExpire() {
        var policy = AppLockPolicy()
        #expect(!policy.permitsAccess(at: start))
        policy.beginUnlock()
        policy.unlocked(at: start)
        #expect(policy.deadline == nil)
        #expect(policy.permitsAccess(at: start.addingTimeInterval(24 * 3600)))
        policy.expireIfNeeded(at: start.addingTimeInterval(24 * 3600))
        #expect(policy.state == .unlocked(until: nil))
    }

    @Test func graceStartsWhenLeavingNotWhenAuthenticating() {
        var policy = AppLockPolicy()
        policy.unlocked(at: start)
        let departure = start.addingTimeInterval(600)
        policy.leaveForeground(at: departure)
        #expect(policy.deadline == departure.addingTimeInterval(300))
        // Becoming backgrounded after inactive must not extend the grace.
        policy.leaveForeground(at: departure.addingTimeInterval(30))
        #expect(policy.deadline == departure.addingTimeInterval(300))
        policy.enterForeground(at: departure.addingTimeInterval(180))
        #expect(policy.state == .unlocked(until: nil))
        #expect(policy.permitsAccess(at: departure.addingTimeInterval(10000)))
    }

    @Test(arguments: [300.0, 301, 1200, 3600])
    func suspendedReturnRequiresAuthentication(elapsed: TimeInterval) {
        var policy = AppLockPolicy()
        policy.unlocked(at: start)
        policy.leaveForeground(at: start)
        // No timer was run while suspended.
        policy.enterForeground(at: start.addingTimeInterval(elapsed))
        #expect(policy.state == .locked)
        #expect(!policy.permitsAccess(at: start.addingTimeInterval(elapsed)))
        policy.beginUnlock()
        policy.unlocked(at: start.addingTimeInterval(elapsed))
        #expect(policy.state == .unlocked(until: nil))
    }

    @Test func explicitLockCannotBeUndoneByForegroundTransition() {
        var policy = AppLockPolicy()
        policy.unlocked(at: start)
        policy.lock()
        policy.leaveForeground(at: start)
        policy.enterForeground(at: start.addingTimeInterval(1))
        #expect(policy.state == .locked)
        #expect(policy.deadline == nil)
    }

    @Test func eachNewAbsenceGetsItsOwnGrace() {
        var policy = AppLockPolicy()
        policy.unlocked(at: start)
        policy.leaveForeground(at: start)
        policy.enterForeground(at: start.addingTimeInterval(299))
        policy.leaveForeground(at: start.addingTimeInterval(600))
        #expect(policy.deadline == start.addingTimeInterval(900))
        policy.expireIfNeeded(at: start.addingTimeInterval(900))
        #expect(policy.state == .locked)
    }

    @Test func authenticationInactiveTransitionDoesNotImmediatelyRelock() {
        var policy = AppLockPolicy()
        policy.beginUnlock()
        policy.leaveForeground(at: start)
        policy.unlocked(at: start.addingTimeInterval(1))
        policy.enterForeground(at: start.addingTimeInterval(2))
        #expect(policy.state == .unlocked(until: nil))
    }
}
