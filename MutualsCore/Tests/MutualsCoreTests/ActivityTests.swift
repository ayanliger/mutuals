import Foundation
import Testing
@testable import MutualsCore

/// JSON for one 2026-format activity record: the post URL, then the owner
/// nested two levels down, with labels as given.
func ownedRecord(_ username: String, _ timestamp: Int, usernameLabel: String = "Username", nameLabel: String = "Name", ownerTitle: String = "Owner") -> String {
    let object: [String: Any] = [
        "timestamp": timestamp,
        "media": [Any](),
        "label_values": [
            ["label": "URL", "value": "https://www.instagram.com/p/Post\(timestamp)/", "href": "https://www.instagram.com/p/Post\(timestamp)/"],
            ["title": ownerTitle, "dict": [["title": "", "dict": [
                ["label": "URL", "value": "https://www.instagram.com/\(username)"],
                ["label": nameLabel, "value": "Display Name \(timestamp % 7)"],
                ["label": usernameLabel, "value": username],
            ]]]],
        ],
        "fbid": "\(timestamp)",
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

struct ActivityParsingTests {
    private func owners(_ json: String) throws -> [String] {
        try ExportParser.parseActivity(Data(json.utf8)).entries.map(\.username)
    }

    @Test func readsLegacyLikesWithEmojiValues() throws {
        let thumbsUp = mojibake("👍")
        let json = #"{"likes_media_likes": [{"title": "creator.one", "string_list_data": [{"href": "https://www.instagram.com/p/AbC/", "value": "\#(thumbsUp)", "timestamp": 1600000000}]}]}"#
        let parsed = try ExportParser.parseActivity(Data(json.utf8))
        #expect(parsed.entries == [ExportParser.ActivityEntry(username: "creator.one", date: Date(timeIntervalSince1970: 1_600_000_000))])
    }

    @Test func readsLegacyAuthorMaps() throws {
        let json = #"{"impressions_history_posts_seen": [{"string_map_data": {"Author": {"value": "creator.one"}, "Time": {"timestamp": 1700000000}}}, {"string_map_data": {"Author": {"value": "creator.two"}, "Time": {"timestamp": 1700000500}}}]}"#
        #expect(try owners(json) == ["creator.one", "creator.two"])
    }

    @Test func prefersMediaOwnerOverOneWordComments() throws {
        // Every comment here is username-shaped, so only the known key decides.
        let rows = [("lindo", "friend.a"), ("top", "friend.b"), ("amei", "friend.c")]
        let records = rows.enumerated().map { index, row in
            #"{"string_map_data": {"Comment": {"value": "\#(row.0)"}, "Media Owner": {"value": "\#(row.1)"}, "Time": {"timestamp": \#(1_650_000_000 + index)}}}"#
        }
        #expect(try owners("[\(records.joined(separator: ","))]") == ["friend.a", "friend.b", "friend.c"])
    }

    @Test func readsNestedOwnerInEnglish() throws {
        let json = "[\(ownedRecord("creator.two", 1_760_000_000)), \(ownedRecord("creator_three", 1_760_000_100))]"
        let parsed = try ExportParser.parseActivity(Data(json.utf8))
        #expect(parsed.entries.map(\.username) == ["creator.two", "creator_three"])
        #expect(parsed.entries[0].date == Date(timeIntervalSince1970: 1_760_000_000))
    }

    @Test func readsNestedOwnerWithTranslatedLabels() throws {
        let portuguese = (0..<4).map { ownedRecord("criador\($0)", 1_760_000_000 + $0, usernameLabel: mojibake("Nome de usuário"), nameLabel: "Nome", ownerTitle: mojibake("Proprietário")) }
        #expect(try owners("[\(portuguese.joined(separator: ","))]") == ["criador0", "criador1", "criador2", "criador3"])

        let greek = (0..<4).map { ownedRecord("page_\($0)", 1_760_000_000 + $0, usernameLabel: mojibake("Χρήστης"), nameLabel: mojibake("Όνομα"), ownerTitle: mojibake("Κάτοχος")) }
        #expect(try owners("[\(greek.joined(separator: ","))]") == ["page_0", "page_1", "page_2", "page_3"])
    }

    @Test func fallsBackToTheOwnersProfileLink() throws {
        let json = #"[{"timestamp": 1760000000, "label_values": [{"label": "URL", "value": "https://www.instagram.com/p/Xy/"}, {"title": "Owner", "dict": [{"title": "", "dict": [{"label": "URL", "value": "https://www.instagram.com/linked.page"}]}]}]}]"#
        #expect(try owners(json) == ["linked.page"])
    }
}

struct ActivityImportTests {
    @Test func keepsOnlyFollowedAccountsAndRecordsCoverage() throws {
        let scratch = try Scratch()
        let base = "export/connections/followers_and_following"
        try scratch.write("[\(legacyEntry("friend", 1_500_000_000))]", to: "\(base)/followers_1.json")
        let following = ["friend", "creator.one", "creator.two"].enumerated().map { titledEntry($1, 1_500_000_000 + $0) }
        try scratch.write(#"{"relationships_following": [\#(following.joined(separator: ","))]}"#, to: "\(base)/following.json")
        // Likes in the old shape: an old like of creator.one and a like of an account not followed.
        // The value is username-shaped on purpose; the owner must still come from the title.
        try scratch.write(
            #"{"likes_media_likes": [{"title": "creator.one", "string_list_data": [{"href": "https://www.instagram.com/p/A/", "value": "x", "timestamp": 1600000000}]}, {"title": "stranger", "string_list_data": [{"href": "https://www.instagram.com/p/B/", "value": "x", "timestamp": 1610000000}]}]}"#,
            to: "export/your_instagram_activity/likes/liked_posts.json"
        )
        // Views in the 2026 shape: a newer view of creator.one and one of friend.
        try scratch.write("[\(ownedRecord("creator.one", 1_760_000_000)), \(ownedRecord("friend", 1_760_000_500))]", to: "export/ads_information/ads_and_topics/posts_viewed.json")
        let archive = try scratch.zip("export", to: "instagram-tester-2026-10-20-x.zip")

        let snapshot = try ExportReader.read([archive], importedAt: utcDate(2026, 10, 25))
        let activity = try #require(snapshot.activity)
        #expect(activity.lastSeen["creator.one"] == Activity(kind: .viewedPost, date: Date(timeIntervalSince1970: 1_760_000_000)))
        #expect(activity.lastSeen["friend"]?.kind == .viewedPost)
        #expect(activity.lastSeen["creator.two"] == nil)
        #expect(activity.lastSeen["stranger"] == nil)
        let likes = try #require(activity.coverage.first { $0.kind == .likedPost })
        #expect(likes.count == 2)
        #expect(likes.first == Date(timeIntervalSince1970: 1_600_000_000))
        #expect(likes.last == Date(timeIntervalSince1970: 1_610_000_000))
    }

    @Test func exportsWithoutActivityHaveNone() throws {
        let scratch = try Scratch()
        let base = "export/connections/followers_and_following"
        try scratch.write("[\(legacyEntry("friend", 1_500_000_000))]", to: "\(base)/followers_1.json")
        try scratch.write(#"{"relationships_following": [\#(titledEntry("friend", 1_500_000_000))]}"#, to: "\(base)/following.json")
        let archive = try scratch.zip("export", to: "instagram-tester-2026-10-20-x.zip")
        #expect(try ExportReader.read([archive]).activity == nil)
    }

    @Test func snapshotsSavedBeforeActivityStillLoad() throws {
        // A snapshot without activity encodes exactly as the earlier model did.
        let old = Snapshot(takenAt: utcDate(2026, 10, 1), followers: [Account(username: "a")], following: [Account(username: "a")])
        let data = try JSONEncoder().encode(old)
        #expect(!String(decoding: data, as: UTF8.self).contains("activity"))
        let decoded = try JSONDecoder().decode(Snapshot.self, from: data)
        #expect(decoded.activity == nil)
        #expect(decoded.following.map(\.username) == ["a"])

        var withActivity = old
        withActivity.activity = ActivitySummary(lastSeen: ["a": Activity(kind: .saved, date: utcDate(2026, 9, 1))], coverage: [])
        let roundTrip = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(withActivity))
        #expect(roundTrip.activity == withActivity.activity)
    }
}

struct QuietAccountTests {
    private let cutoff = utcDate(2025, 10, 1)

    private func report(_ lastSeen: [String: Activity], mutuals: [String] = []) throws -> Report {
        let following = [
            Account(username: "recent", since: utcDate(2018, 1, 1)),
            Account(username: "stale", since: utcDate(2018, 1, 1)),
            Account(username: "never", since: utcDate(2016, 1, 1)),
            Account(username: "new.follow", since: utcDate(2026, 3, 1)),
            Account(username: "quiet.friend", since: utcDate(2015, 1, 1)),
        ]
        let snapshot = Snapshot(
            takenAt: utcDate(2026, 10, 1),
            followers: mutuals.map { Account(username: $0) },
            following: following,
            activity: ActivitySummary(lastSeen: lastSeen, coverage: [ActivityCoverage(kind: .likedPost, first: utcDate(2015, 1, 1), last: utcDate(2026, 10, 1), count: 10)])
        )
        return try #require(Analyzer.report(for: [snapshot]))
    }

    @Test func listsAccountsQuietSinceTheCutoff() throws {
        let report = try report([
            "recent": Activity(kind: .viewedPost, date: utcDate(2026, 9, 1)),
            "stale": Activity(kind: .likedPost, date: utcDate(2022, 3, 1)),
        ], mutuals: ["quiet.friend"])

        let quiet = report.quietAccounts(since: cutoff, includeMutuals: false)
        // "never" went quiet when followed in 2016, before "stale"'s last like in 2022.
        #expect(quiet.map(\.username) == ["never", "stale"])
        #expect(quiet[1].lastSeen?.kind == .likedPost)

        let withMutuals = report.quietAccounts(since: cutoff, includeMutuals: true)
        #expect(withMutuals.map(\.username) == ["quiet.friend", "never", "stale"])
        #expect(withMutuals[0].followsYou)
    }

    @Test func ordersByTheLaterOfLastSeenAndFollowDate() {
        let likedBeforeFollowing = QuietItem(username: "a", name: nil, followedAt: utcDate(2020, 8, 1), lastSeen: Activity(kind: .likedPost, date: utcDate(2018, 1, 1)), followsYou: false)
        #expect(likedBeforeFollowing.quietSince == utcDate(2020, 8, 1))
    }

    @Test func isEmptyWithoutActivityData() throws {
        let snapshot = Snapshot(takenAt: utcDate(2026, 10, 1), followers: [], following: [Account(username: "x", since: utcDate(2015, 1, 1))])
        let report = try #require(Analyzer.report(for: [snapshot]))
        #expect(report.activity == nil)
        #expect(report.quietAccounts(since: cutoff, includeMutuals: true).isEmpty)
    }

    @Test func remembersActivityFromEarlierExports() throws {
        let following = [Account(username: "x", since: utcDate(2015, 1, 1))]
        let coverage = [ActivityCoverage(kind: .viewedPost, first: utcDate(2026, 7, 1), last: utcDate(2026, 10, 1), count: 5)]
        let earlier = Snapshot(takenAt: utcDate(2026, 3, 1), followers: [], following: following,
                               activity: ActivitySummary(lastSeen: ["x": Activity(kind: .likedPost, date: utcDate(2026, 2, 20))], coverage: coverage))
        let later = Snapshot(takenAt: utcDate(2026, 10, 1), followers: [], following: following,
                             activity: ActivitySummary(lastSeen: [:], coverage: coverage))
        let report = try #require(Analyzer.report(for: [earlier, later]))
        #expect(report.activity?.lastSeen["x"]?.date == utcDate(2026, 2, 20))
        #expect(report.quietAccounts(since: cutoff, includeMutuals: false).isEmpty)
    }
}
