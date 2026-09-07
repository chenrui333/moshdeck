import Testing

@testable import MoshDeckCore

@Test func reconnectCannotRecreateALostTask() throws {
    let initial = SessionIntent.createOrAttach(name: "work")
    #expect(try initial.command() == "exec 'tmux' new-session -A -s 'work'")
    #expect(try initial.reconnectIntent.command() == "exec 'tmux' attach-session -t '=work'")
    #expect(try SessionIntent.shell.command() == nil)
}

@Test(arguments: [
    "", "work; touch pwned", "$(whoami)", "work\nexit", "work:0", "=work", String(repeating: "x", count: 65),
])
func rejectNamesThatChangeCommandOrTarget(name: String) {
    #expect(throws: SessionConfigurationError.self) { try SessionIntent.attach(name: name).command() }
}

@Test func executablePathIsShellQuoted() throws {
    #expect(
        try SessionIntent.attach(name: "work").command(tmuxExecutable: "/tmp/owner's tmux")
            == "exec '/tmp/owner'\\''s tmux' attach-session -t '=work'")
}

@Test func lateReconnectAndPasteCannotCrossGeneration() {
    var state = ConnectionGeneration()
    let first = state.begin()
    #expect(!state.permitsInput(for: first))
    let firstReady = state.ready(first)
    #expect(firstReady)
    #expect(state.permitsInput(for: first))
    state.invalidate()  // Background/lock or disconnect during an unfinished paste.
    #expect(!state.permitsInput(for: first))
    let second = state.begin()
    let staleReady = state.ready(first)
    #expect(!staleReady)
    #expect(!state.permitsInput(for: second))
    let secondReady = state.ready(second)
    #expect(secondReady)
    #expect(!state.permitsInput(for: first))
    #expect(state.permitsInput(for: second))
}
