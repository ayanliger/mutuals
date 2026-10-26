import Foundation

/// Invented accounts for trying the app before a real export arrives. The app
/// never saves these snapshots and never opens these usernames in Instagram.
public enum SampleData {
    /// Two exports five weeks apart, shaped like a personal account that
    /// followed friends first and creators later.
    public static func snapshots(now: Date = Date()) -> [Snapshot] {
        var random = SplitMix64(seed: 2026)
        var usedTimes = Set<Int>()
        func moment(_ start: (Int, Int), _ end: (Int, Int)) -> Date {
            let from = utc(start.0, start.1)
            let to = min(utc(end.0, end.1), now.addingTimeInterval(-40 * 86_400))
            while true {
                let seconds = Int(Double.random(in: from.timeIntervalSince1970..<to.timeIntervalSince1970, using: &random))
                if usedTimes.insert(seconds).inserted { return Date(timeIntervalSince1970: TimeInterval(seconds)) }
            }
        }

        let people = names(count: 220, using: &random)
        let creators = creatorNames(count: 170, using: &random)
        var nextPerson = people.makeIterator()
        var nextCreator = creators.makeIterator()
        func person() -> (String, String) { nextPerson.next()! }
        func creator() -> (String, String) { nextCreator.next()! }

        var followingA: [Account] = []
        var followersA: [Account] = []
        var followingB: [Account] = []
        var followersB: [Account] = []
        func follow(_ entry: (String, String), at date: Date, mutual: Bool, inA: Bool = true, followsInA: Bool? = nil) {
            let account = Account(username: entry.0, name: entry.1, since: date)
            if inA { followingA.append(account) }
            followingB.append(account)
            let follower = Account(username: entry.0, name: entry.1, since: date.addingTimeInterval(-Double.random(in: 3_600...400_000, using: &random)))
            if followsInA ?? mutual { followersA.append(follower) }
            if mutual { followersB.append(follower) }
        }

        // Friends followed in the account's first years, almost all mutual.
        for _ in 0..<64 { follow(person(), at: moment((2014, 2), (2016, 11)), mutual: true) }
        // Friends who unfollowed between the two exports.
        var unfollowers: [(String, String)] = []
        for _ in 0..<5 {
            let entry = person()
            unfollowers.append(entry)
            follow(entry, at: moment((2014, 3), (2016, 9)), mutual: false, followsInA: true)
        }
        // Accounts from the same years that never followed back.
        for _ in 0..<6 { follow(person(), at: moment((2014, 4), (2016, 10)), mutual: false) }
        // Later follows: mostly creators, some acquaintances.
        for _ in 0..<26 { follow(person(), at: moment((2017, 1), (2026, 8)), mutual: true) }
        for _ in 0..<160 { follow(creator(), at: moment((2017, 1), (2026, 8)), mutual: false) }

        let closeFriends = (0..<2).map { _ in person() }
        let requested = (0..<2).map { _ in person() }
        let asking = person()
        let hidden = person()
        for entry in closeFriends + requested + [asking, hidden] {
            follow(entry, at: moment((2018, 1), (2025, 12)), mutual: false)
        }

        // One unfollower also changed username; the follow time stays the same.
        let renamed = unfollowers[0]
        if let index = followingB.firstIndex(where: { $0.username == renamed.0 }) {
            followingB[index].username = renamed.0 + ".studio"
        }

        // Followers you don't follow, a few of whom left or arrived between exports.
        for index in 0..<95 {
            let entry = person()
            let account = Account(username: entry.0, name: entry.1, since: moment((2015, 1), (2026, 8)))
            if index < 92 { followersA.append(account) }
            if index >= 2 { followersB.append(account) }
        }

        let pending = (0..<3).map { _ in
            let entry = person()
            return Account(username: entry.0, name: entry.1, since: moment((2019, 1), (2024, 12)))
        }

        let takenB = now.addingTimeInterval(-86_400)
        let takenA = takenB.addingTimeInterval(-35 * 86_400)
        // Activity in the second export: most accounts seen in the last three
        // months, some last liked or saved years ago, a few never seen.
        let viewedFrom = takenB.addingTimeInterval(-90 * 86_400)
        var lastSeen: [String: Activity] = [:]
        for account in followingB {
            let roll = Double.random(in: 0..<1, using: &random)
            if roll < 0.6 {
                let seconds = Double.random(in: viewedFrom.timeIntervalSince1970..<takenB.timeIntervalSince1970, using: &random)
                lastSeen[account.username] = Activity(kind: .viewedPost, date: Date(timeIntervalSince1970: seconds))
            } else if roll < 0.86 {
                let kind = [ActivityKind.likedPost, .storyLike, .saved, .comment].randomElement(using: &random)!
                lastSeen[account.username] = Activity(kind: kind, date: moment((2018, 1), (2025, 6)))
            }
        }
        let activity = ActivitySummary(lastSeen: lastSeen, coverage: [
            ActivityCoverage(kind: .likedPost, first: utc(2014, 5), last: takenB, count: 3_412),
            ActivityCoverage(kind: .comment, first: utc(2015, 2), last: takenB, count: 241),
            ActivityCoverage(kind: .storyLike, first: utc(2019, 8), last: takenB, count: 1_870),
            ActivityCoverage(kind: .saved, first: utc(2016, 3), last: takenB, count: 388),
            ActivityCoverage(kind: .viewedPost, first: viewedFrom, last: takenB, count: 9_150),
            ActivityCoverage(kind: .viewedVideo, first: viewedFrom, last: takenB, count: 4_020),
        ])

        func snapshot(taken: Date, followers: [Account], following: [Account], activity: ActivitySummary?) -> Snapshot {
            Snapshot(
                owner: "sample",
                takenAt: taken,
                importedAt: taken,
                sourceName: "Sample data",
                followers: followers,
                following: following,
                closeFriends: Set(closeFriends.map(\.0)),
                hiddenStoryFrom: [hidden.0],
                pendingRequests: pending,
                sentRequests: Set(requested.map(\.0)),
                receivedRequests: [asking.0],
                isSample: true,
                activity: activity
            )
        }
        return [
            snapshot(taken: takenA, followers: followersA, following: followingA, activity: nil),
            snapshot(taken: takenB, followers: followersB, following: followingB, activity: activity),
        ]
    }

    private static func utc(_ year: Int, _ month: Int) -> Date {
        var components = DateComponents(year: year, month: month, day: 1)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private static func names(count: Int, using random: inout SplitMix64) -> [(String, String)] {
        let first = ["ana", "bruno", "carla", "diego", "elisa", "felipe", "gabi", "hugo", "isa", "joao", "karen", "lucas",
                     "marina", "nina", "otavio", "paula", "rafa", "sofia", "tiago", "vivi", "caio", "duda", "leo", "bia"]
        let last = ["lima", "costa", "souza", "reis", "melo", "rocha", "dias", "nunes", "pires", "alves", "barros", "freitas"]
        let joins = [".", "_", "", "."]
        var seen = Set<String>()
        var result: [(String, String)] = []
        while result.count < count {
            let f = first.randomElement(using: &random)!
            let l = last.randomElement(using: &random)!
            let handle = f + joins.randomElement(using: &random)! + l + (Bool.random(using: &random) ? "" : String(Int.random(in: 1...99, using: &random)))
            guard seen.insert(handle).inserted else { continue }
            result.append((handle, f.capitalized + " " + l.capitalized))
        }
        return result
    }

    private static func creatorNames(count: Int, using random: inout SplitMix64) -> [(String, String)] {
        let left = ["studio", "daily", "atelier", "field", "orbit", "paper", "slow", "night", "north", "little", "wild", "urban"]
        let right = ["ceramics", "kitchen", "trail", "film", "type", "plants", "bikes", "coffee", "jazz", "lens", "ink", "bread",
                     "maps", "yoga", "chess", "garden", "synths", "knits"]
        var seen = Set<String>()
        var result: [(String, String)] = []
        while result.count < count {
            let l = left.randomElement(using: &random)!
            let r = right.randomElement(using: &random)!
            let handle = [l + "." + r, l + r, r + "_" + l, "the" + l + r].randomElement(using: &random)!
            guard seen.insert(handle).inserted else { continue }
            result.append((handle, l.capitalized + " " + r.capitalized))
        }
        return result
    }
}

/// Deterministic generator so the sample looks the same on every launch.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
