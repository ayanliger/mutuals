import Foundation
import Testing
@testable import MutualsCore

struct AnalyzerTests {
    private func account(_ username: String, _ timestamp: Int? = nil) -> Account {
        Account(username: username, since: timestamp.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }

    private func snapshot(day: Int, followers: [Account], following: [Account], closeFriends: Set<String> = []) -> Snapshot {
        Snapshot(takenAt: utcDate(2026, 9, day), importedAt: utcDate(2026, 9, day), followers: followers, following: following, closeFriends: closeFriends)
    }

    @Test func listsAccountsThatDoNotFollowBack() throws {
        let latest = snapshot(day: 1, followers: [account("a"), account("fan")], following: [account("a"), account("b"), account("c")], closeFriends: ["c"])
        let report = try #require(Analyzer.report(for: [latest]))
        #expect(report.mutualCount == 1)
        #expect(Set(report.items.map(\.username)) == ["b", "c"])
        #expect(report.items(in: .likelyPersonal).map(\.username) == ["c"])
        #expect(report.items(in: .noSignal).map(\.username) == ["b"])
        #expect(report.changes == nil)
    }

    @Test func findsPeopleWhoUnfollowedYou() throws {
        let first = snapshot(day: 1, followers: [account("friend"), account("left")], following: [account("friend"), account("left"), account("creator")])
        let second = snapshot(day: 15, followers: [account("friend")], following: [account("friend"), account("left"), account("creator")])
        let report = try #require(Analyzer.report(for: [second, first]))

        let unfollowed = report.items(in: .unfollowedYou)
        #expect(unfollowed.map(\.username) == ["left"])
        #expect(unfollowed[0].signals.contains(.unfollowedYou(lastSeen: utcDate(2026, 9, 1), goneBy: utcDate(2026, 9, 15))))
        #expect(report.items(in: .noSignal).map(\.username) == ["creator"])
        #expect(report.changes?.lostFollowers.map(\.username) == ["left"])
    }

    @Test func remembersTheLastExportWithTheFollow() throws {
        let following = [account("friend"), account("left")]
        let first = snapshot(day: 1, followers: [account("left")], following: following)
        let second = snapshot(day: 10, followers: [account("left")], following: following)
        let third = snapshot(day: 20, followers: [], following: following)
        let report = try #require(Analyzer.report(for: [first, third, second]))
        let item = try #require(report.items.first { $0.username == "left" })
        #expect(item.signals.first == .unfollowedYou(lastSeen: utcDate(2026, 9, 10), goneBy: utcDate(2026, 9, 20)))
    }

    @Test func followsRenamesThroughFollowTimes() throws {
        let first = snapshot(day: 1, followers: [account("old.name", 900)], following: [account("old.name", 1_000), account("other", 2_000)])
        let second = snapshot(day: 15, followers: [], following: [account("new.name", 1_000), account("other", 2_000)])
        let report = try #require(Analyzer.report(for: [first, second]))

        let item = try #require(report.items.first { $0.username == "new.name" })
        #expect(item.group == .unfollowedYou)
        #expect(item.signals.contains(.renamed(from: "old.name")))
        #expect(report.changes?.renames == [SnapshotDiff.Rename(old: "old.name", new: "new.name")])
        #expect(report.changes?.unfollowedByYou.isEmpty == true)
    }

    @Test func ignoresAmbiguousFollowTimes() {
        let renames = Analyzer.renames(
            from: [account("a", 5), account("b", 5)],
            to: [account("c", 5)]
        )
        #expect(renames.isEmpty)
    }

    @Test func flagsFollowsMadeAlongsideFriends() throws {
        // 2015: 40 follows, all mutual except two. 2023: 60 follows, none mutual.
        var following: [Account] = []
        var followers: [Account] = []
        for index in 0..<40 {
            let name = "friend\(index)"
            following.append(account(name, 1_420_000_000 + index * 86_400))
            if index != 10 && index != 30 { followers.append(account(name)) }
        }
        for index in 0..<60 {
            following.append(account("creator\(index)", 1_680_000_000 + index * 86_400))
        }
        let report = try #require(Analyzer.report(for: [snapshot(day: 1, followers: followers, following: following)]))
        #expect(Set(report.items(in: .likelyPersonal).map(\.username)) == ["friend10", "friend30"])
        #expect(report.items(in: .noSignal).count == 60)
    }

    @Test func doesNotFlagPeriodsForMostlyMutualAccounts() {
        // When 90% of follows are mutual everywhere, no period stands out.
        var following: [Account] = []
        var followers = Set<String>()
        for index in 0..<100 {
            following.append(account("u\(index)", 1_500_000_000 + index * 3_600))
            if index % 10 != 0 { followers.insert("u\(index)") }
        }
        let rates = Analyzer.periodMutualRates(following: following, followers: followers)
        #expect(rates.count == 10)
        #expect(rates.values.allSatisfy { $0 >= 0.8 })
        let report = Analyzer.report(for: [snapshot(day: 1, followers: followers.map { account($0) }, following: following)])
        #expect(report?.items(in: .likelyPersonal).isEmpty == true)
    }

    @Test func sampleDataTellsTheIntendedStory() throws {
        let snapshots = SampleData.snapshots(now: utcDate(2026, 10, 25))
        let report = try #require(Analyzer.report(for: snapshots))
        let unfollowed = report.items(in: .unfollowedYou)
        #expect(unfollowed.count == 5)
        #expect(unfollowed.contains { $0.signals.contains { if case .renamed = $0 { true } else { false } } })
        #expect(report.items(in: .likelyPersonal).count >= 10)
        #expect(report.items(in: .noSignal).count >= 150)
        #expect(report.pendingRequests.count == 3)
        #expect(report.changes?.lostFollowers.count == 7)
        #expect(report.changes?.newFollowers.count == 3)
    }
}
