import Foundation
import Testing
@testable import MutualsCore

struct ExportParserTests {
    @Test func readsLegacyEntries() throws {
        let json = "[\(legacyEntry("alice", 1_500_000_000)), \(legacyEntry("bob.smith", 1_500_000_100))]"
        let parsed = try ExportParser.parseJSON(Data(json.utf8))
        #expect(parsed.accounts.map(\.username) == ["alice", "bob.smith"])
        #expect(parsed.accounts[0].since == Date(timeIntervalSince1970: 1_500_000_000))
    }

    @Test func readsTitledEntriesInsideWrapper() throws {
        let json = #"{"relationships_following": [\#(titledEntry("alice", 1_600_000_000)), \#(titledEntry("c_d", 1_600_000_001))]}"#
        let parsed = try ExportParser.parseJSON(Data(json.utf8))
        #expect(parsed.accounts.map(\.username) == ["alice", "c_d"])
        #expect(parsed.accounts[1].since == Date(timeIntervalSince1970: 1_600_000_001))
    }

    @Test func readsEnglishLabelledEntries() throws {
        let entries = (0..<5).map { labelledEntry(usernameLabel: "Username", username: "user\($0)", nameLabel: "Name", name: "Person \($0)", timestamp: 1_700_000_000 + $0) }
        let parsed = try ExportParser.parseJSON(Data("[\(entries.joined(separator: ","))]".utf8))
        #expect(parsed.accounts.map(\.username) == ["user0", "user1", "user2", "user3", "user4"])
        #expect(parsed.accounts[2].name == "Person 2")
        #expect(parsed.accounts[2].fbid == "1000001700000002")
    }

    @Test func readsPortugueseLabelsWithDoubleEncoding() throws {
        let rows = [("joao.silva", "João Silva"), ("maria_eduarda", "Maria Eduarda"), ("ana", "ana"), ("pedro.h", "Pedro Henrique"), ("bia_s", "Beatriz Souza")]
        let entries = rows.enumerated().map { index, row in
            labelledEntry(usernameLabel: mojibake("Nome de usuário"), username: row.0, nameLabel: mojibake("Nome"), name: mojibake(row.1), timestamp: 1_700_000_000 + index)
        }
        let json = #"{"relationships_following": [\#(entries.joined(separator: ","))]}"#
        let parsed = try ExportParser.parseJSON(Data(json.utf8))
        #expect(parsed.accounts.map(\.username) == rows.map(\.0))
        #expect(parsed.accounts[0].name == "João Silva")
    }

    @Test func infersUsernameLabelInUnknownLanguage() throws {
        // A display name that is itself username-shaped ("ninthperson") must not confuse inference.
        let rows = ["sample_a", "sample_b", "sample_c", "sample_d", "sample_e", "sample_f", "sample_g", "sample_h", "sample_i"]
        let names = ["A Display Name", "Another Person", "Third One", "Fourth Person", "Fifth", "Sixth Person", "Seventh Person", "Eighth Person", "ninthperson"]
        let entries = zip(rows, names).enumerated().map { index, pair in
            labelledEntry(usernameLabel: mojibake("Χρήστης"), username: pair.0, nameLabel: mojibake("Όνομα"), name: pair.1, timestamp: 1_700_000_000 + index)
        }
        let parsed = try ExportParser.parseJSON(Data("[\(entries.joined(separator: ","))]".utf8))
        #expect(parsed.accounts.map(\.username) == rows)
        #expect(parsed.accounts.last?.name == "ninthperson")
    }

    @Test func reportsRecordsWhoseUsernameCannotBeFound() throws {
        let json = #"[{"timestamp": 1, "label_values": [{"label": "X", "value": "Two Words"}, {"label": "Y", "value": "More Words"}]}]"#
        let parsed = try ExportParser.parseJSON(Data(json.utf8))
        #expect(parsed.accounts.isEmpty)
        #expect(parsed.recordCount == 1)
    }

    @Test func rejectsInvalidJSON() {
        #expect(throws: ExportReadError.notJSON) { try ExportParser.parseJSON(Data("<html>".utf8)) }
    }

    @Test func readsHTMLExports() {
        let html = """
        <html><body>
        <div class="pam"><div><a target="_blank" href="https://www.instagram.com/alice">alice</a></div><div>Oct 25, 2026 10:00 am</div></div>
        <div class="pam"><div><a target="_blank" href="https://www.instagram.com/_u/bob.smith">bob.smith</a></div></div>
        <div class="pam"><div><a target="_blank" href="https://www.instagram.com/alice">alice</a></div></div>
        <a href="https://www.instagram.com/p/Cxyz123/">a post</a>
        </body></html>
        """
        let parsed = ExportParser.parseHTML(Data(html.utf8))
        #expect(parsed.accounts.map(\.username) == ["alice", "bob.smith"])
        #expect(parsed.accounts.allSatisfy { $0.since == nil })
    }

    @Test(arguments: [
        ("connections/followers_and_following/following.json", ExportFileKind.following, false),
        ("connections/followers_and_following/followers_1.json", .followers, false),
        ("followers_12.html", .followers, true),
        ("x/close_friends.json", .closeFriends, false),
        ("x/hide_story_from.json", .hiddenStoryFrom, false),
        ("x/pending_follow_requests.json", .pendingRequests, false),
        ("x/recent_follow_requests.json", .sentRequests, false),
        ("x/follow_requests_you've_received.json", .receivedRequests, false),
        ("x/recently_unfollowed_profiles.json", .recentlyUnfollowed, false),
    ])
    func classifiesFiles(path: String, kind: ExportFileKind, isHTML: Bool) throws {
        let match = try #require(ExportFileKind.classify(path))
        #expect(match.kind == kind)
        #expect(match.isHTML == isHTML)
    }

    @Test func ignoresOtherFiles() {
        #expect(ExportFileKind.classify("x/following_hashtags.json") == nil)
        #expect(ExportFileKind.classify("x/followers_x.json") == nil)
        #expect(ExportFileKind.classify("__MACOSX/x/following.json") == nil)
        #expect(ExportFileKind.classify("media/posts/photo.jpg") == nil)
    }

    @Test func readsArchiveName() throws {
        let parsed = try #require(ExportReader.exportName("instagram-ayan.liger_-2026-10-25-AbC123xyz.zip"))
        #expect(parsed.owner == "ayan.liger_")
        #expect(parsed.date == utcDate(2026, 10, 25, 12))
        #expect(ExportReader.exportName("meta-2026-10-25.zip") == nil)
    }

    @Test func repairsMojibakeOnly() {
        #expect(ExportParser.repairMojibake(mojibake("Conceição")) == "Conceição")
        #expect(ExportParser.repairMojibake("Conceição") == "Conceição")
        #expect(ExportParser.repairMojibake("plain") == "plain")
    }
}
