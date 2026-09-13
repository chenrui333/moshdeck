import Foundation
import Testing

@testable import MoshDeckCore

@Suite struct TmuxSessionListingTests {
    @Test func parsesBoundedMetadataAndMarksUnsupportedNames() throws {
        let rows = try TmuxSessionListing.parse(Data("work|2|2\nhome.brew|1|0\ninfra|3|1\n".utf8))
        #expect(rows.map(\.name) == ["home.brew", "infra", "work"])
        #expect(rows.last?.attachedClients == 2)
        #expect(rows.first?.canAttach == false)
        #expect(rows.last?.canAttach == true)
    }
    @Test(arguments: ["work|1|1\nwork|2|0\n", "work|0|1", "work|1|-1", "banner", "work\u{1b}|1|0"])
    func rejectsMalformedOrAmbiguousRows(text: String) {
        #expect(throws: TmuxListingError.invalidResponse) { try TmuxSessionListing.parse(Data(text.utf8)) }
    }
    @Test func boundsOutputAndQuotesExecutable() throws {
        #expect(throws: TmuxListingError.outputLimit) {
            try TmuxSessionListing.parse(Data(repeating: 65, count: TmuxSessionListing.maximumBytes + 1))
        }
        let command = try TmuxSessionListing.command(executable: "/a'b/tmux")
        #expect(command.hasPrefix("exec '/a'\\''b/tmux' -u list-sessions"))
        #expect(command.contains("#{session_name}|#{session_windows}|#{session_attached}"))
        #expect(throws: SessionConfigurationError.invalidExecutable) {
            try TmuxSessionListing.command(executable: "tmux\nfalse")
        }
    }
}
