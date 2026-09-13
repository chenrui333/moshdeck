import Foundation

/// Gesture intent only. No I/O, connection ownership, or queued remote actions.
public enum SessionSwipe {
    public static func isHorizontal(x: Double, y: Double) -> Bool {
        abs(x) >= 8 && abs(x) > abs(y) * 1.8
    }

    public static func threshold(width: Double) -> Double { max(90, width * 0.28) }

    public static func commits(x: Double, y: Double, velocityX: Double, width: Double) -> Bool {
        guard isHorizontal(x: x, y: y) else { return false }
        return abs(x) >= threshold(width: width)
            || (abs(x) >= 40 && abs(velocityX) >= 900 && x * velocityX > 0)
    }

    /// Uses picker order and never wraps. Unsupported names stay visible in the
    /// picker but block paging at that boundary rather than silently skipping it.
    public static func target(in sessions: [TmuxSessionSummary], current: String, x: Double) -> TmuxSessionSummary? {
        guard let index = sessions.firstIndex(where: { $0.name == current }), x != 0 else { return nil }
        let next = index + (x < 0 ? 1 : -1)
        guard sessions.indices.contains(next), sessions[next].canAttach else { return nil }
        return sessions[next]
    }
}
