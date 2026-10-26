import Foundation
import Testing
@testable import MutualsCore

struct ExportReaderTests {
    private func writeExport(in scratch: Scratch, folder: String = "export", followers: Bool = true) throws {
        let base = "\(folder)/connections/followers_and_following"
        if followers {
            try scratch.write("[\(legacyEntry("mutual.one", 1_600_000_000)), \(legacyEntry("fan.only", 1_600_000_500))]", to: "\(base)/followers_1.json")
            try scratch.write("[\(legacyEntry("mutual.two", 1_600_000_900))]", to: "\(base)/followers_2.json")
        }
        let following = ["mutual.one", "mutual.two", "creator", "old.friend"].enumerated().map { titledEntry($1, 1_500_000_000 + $0) }
        try scratch.write(#"{"relationships_following": [\#(following.joined(separator: ","))]}"#, to: "\(base)/following.json")
        try scratch.write(#"{"relationships_close_friends": [\#(legacyEntry("old.friend", 1))]}"#, to: "\(base)/close_friends.json")
        try scratch.write(#"{"relationships_follow_requests_sent": [\#(legacyEntry("private.person", 1_650_000_000))]}"#, to: "\(base)/pending_follow_requests.json")
        try scratch.write(#"{"relationships_permanent_follow_requests": [\#(legacyEntry("old.friend", 1_400_000_000))]}"#, to: "\(base)/recent_follow_requests.json")
        try scratch.write(#"{"relationships_follow_requests_received": [\#(legacyEntry("asker", 1_690_000_000))]}"#, to: "\(base)/follow_requests_you've_received.json")
        // A same-named file elsewhere must not replace the real list.
        try scratch.write("[\(legacyEntry("threads.only", 1))]", to: "\(folder)/your_instagram_activity/threads/following.json")
        try scratch.write("not json", to: "\(folder)/media/posts/1.jpg")
    }

    @Test func readsZippedExport() throws {
        let scratch = try Scratch()
        try writeExport(in: scratch)
        let archive = try scratch.zip("export", to: "instagram-tester-2026-10-20-AbC123.zip")
        let importedAt = utcDate(2026, 10, 25)

        let snapshot = try ExportReader.read([archive], importedAt: importedAt)
        #expect(snapshot.owner == "tester")
        #expect(snapshot.followers.map(\.username) == ["mutual.one", "fan.only", "mutual.two"])
        #expect(snapshot.following.map(\.username) == ["mutual.one", "mutual.two", "creator", "old.friend"])
        #expect(snapshot.closeFriends == ["old.friend"])
        #expect(snapshot.pendingRequests.map(\.username) == ["private.person"])
        #expect(snapshot.sentRequests == ["old.friend"])
        #expect(snapshot.receivedRequests == ["asker"])
        #expect(snapshot.sourceName == "instagram-tester-2026-10-20-AbC123.zip")
        #expect(!snapshot.fromHTML)
        // Entry timestamps are today's, five days away from the name's date, so the name wins.
        if abs(Date().timeIntervalSince(utcDate(2026, 10, 20, 12))) > 3 * 86_400 {
            #expect(snapshot.takenAt == utcDate(2026, 10, 20, 12))
        }
    }

    @Test func readsUnzippedFolder() throws {
        let scratch = try Scratch()
        try writeExport(in: scratch, folder: "instagram-tester-2026-10-20-AbC123")
        let snapshot = try ExportReader.read([scratch.url.appendingPathComponent("instagram-tester-2026-10-20-AbC123")], importedAt: utcDate(2026, 10, 25))
        #expect(snapshot.owner == "tester")
        #expect(snapshot.takenAt == utcDate(2026, 10, 20, 12))
        #expect(snapshot.following.count == 4)
    }

    @Test func readsLooseFiles() throws {
        let scratch = try Scratch()
        try writeExport(in: scratch)
        let base = scratch.url.appendingPathComponent("export/connections/followers_and_following")
        let files = ["followers_1.json", "following.json"].map { base.appendingPathComponent($0) }
        let importedAt = utcDate(2026, 10, 25)
        let snapshot = try ExportReader.read(files, importedAt: importedAt)
        #expect(snapshot.owner == nil)
        #expect(snapshot.takenAt == importedAt)
        #expect(snapshot.followers.count == 2)
    }

    @Test func explainsMissingFollowers() throws {
        let scratch = try Scratch()
        try writeExport(in: scratch, followers: false)
        let archive = try scratch.zip("export", to: "instagram-tester-2026-10-20-x.zip")
        #expect(throws: ExportReadError.missingFollowers) { try ExportReader.read([archive]) }
    }

    @Test func explainsUnrelatedArchive() throws {
        let scratch = try Scratch()
        try scratch.write("hello", to: "other/readme.txt")
        let archive = try scratch.zip("other", to: "other.zip")
        #expect(throws: ExportReadError.noRelationshipFiles) { try ExportReader.read([archive]) }
    }

    @Test func prefersJSONOverHTML() throws {
        let scratch = try Scratch()
        try writeExport(in: scratch)
        try scratch.write(#"<a href="https://www.instagram.com/html.only">x</a>"#, to: "export/connections/followers_and_following/following.html")
        let archive = try scratch.zip("export", to: "instagram-tester-2026-10-20-x.zip")
        let snapshot = try ExportReader.read([archive])
        #expect(!snapshot.following.map(\.username).contains("html.only"))
    }
}
