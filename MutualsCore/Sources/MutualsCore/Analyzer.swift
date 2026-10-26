import Foundation

/// Evidence that an account which doesn't follow you back is a person you know
/// rather than a creator or brand.
public enum Signal: Hashable, Sendable {
    /// They followed you in an earlier export and not in the latest one.
    case unfollowedYou(lastSeen: Date, goneBy: Date)
    /// They changed username since that earlier export.
    case renamed(from: String)
    case closeFriend
    case hiddenFromStory
    /// You asked to follow them and they haven't answered.
    case requestPending
    /// You sent them a follow request at some point, so the account is or was private.
    case requestedToFollow
    /// They asked to follow you and the request is waiting for your approval.
    case wantsToFollowYou
    /// You followed them during a stretch when most of the accounts you
    /// followed follow you back, which is how following friends looks.
    case followedWithFriends(rate: Double)

    /// How much this signal counts towards "personal", for ordering.
    var weight: Double {
        switch self {
        case .unfollowedYou: 10
        case .closeFriend, .wantsToFollowYou: 3
        case .hiddenFromStory, .requestedToFollow: 2
        case .requestPending: 1.5
        case .followedWithFriends(let rate): rate
        case .renamed: 0
        }
    }
}

/// An account you follow that doesn't follow you back.
public struct ReportItem: Identifiable, Hashable, Sendable {
    public enum Group: Int, Comparable, Sendable {
        case unfollowedYou
        case likelyPersonal
        case noSignal

        public static func < (lhs: Group, rhs: Group) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var id: String { username }
    public let username: String
    public let name: String?
    /// When you followed them.
    public let followedAt: Date?
    public let signals: [Signal]
    public let group: Group

    public var weight: Double { signals.reduce(0) { $0 + $1.weight } }

    /// The export date after which they no longer followed you.
    public var goneBy: Date? {
        signals.lazy.compactMap { if case .unfollowedYou(_, let date) = $0 { date } else { nil } }.first
    }
}

/// An account you follow and the last time its content showed up in your activity.
public struct QuietItem: Identifiable, Hashable, Sendable {
    public var id: String { username }
    public let username: String
    public let name: String?
    public let followedAt: Date?
    public let lastSeen: Activity?
    public let followsYou: Bool

    /// When the account went quiet: its last activity or the follow date,
    /// whichever is later. A like from before you followed doesn't make an
    /// account quieter than the follow itself.
    public var quietSince: Date? { [lastSeen?.date, followedAt].compactMap { $0 }.max() }
}

/// Your activity merged across all exports of one account.
public struct ActivityOverview: Sendable {
    /// Latest activity per account, across every export that had activity logs.
    public let lastSeen: [String: Activity]
    /// One span per log, from the earliest to the latest entry in any export.
    public let coverage: [ActivityCoverage]
}

/// Who started and stopped following between two exports.
public struct SnapshotDiff: Sendable {
    public struct Rename: Hashable, Sendable {
        public let old: String
        public let new: String
    }

    public let lostFollowers: [Account]
    public let newFollowers: [Account]
    public let unfollowedByYou: [Account]
    public let followedByYou: [Account]
    public let renames: [Rename]
}

/// The analysis of the latest export for one account.
public struct Report: Sendable {
    public let snapshot: Snapshot
    public let previous: Snapshot?
    public let mutualCount: Int
    /// Accounts you follow that don't follow you back, ordered by group and evidence.
    public let items: [ReportItem]
    /// Follow requests you sent that were never answered.
    public let pendingRequests: [Account]
    /// Changes since the previous export, when there is one.
    public let changes: SnapshotDiff?
    /// Nil until an export with activity logs has been imported.
    public let activity: ActivityOverview?

    public var followingCount: Int { snapshot.following.count }
    public var followersCount: Int { snapshot.followers.count }

    public func items(in group: ReportItem.Group) -> [ReportItem] {
        items.filter { $0.group == group }
    }

    /// Accounts you follow with no activity of yours since `cutoff`, the
    /// longest quiet first. Accounts followed after the cutoff haven't had
    /// the time to go quiet and are left out.
    public func quietAccounts(since cutoff: Date, includeMutuals: Bool) -> [QuietItem] {
        guard let activity else { return [] }
        let followers = Set(snapshot.followers.map(\.username))
        return snapshot.following
            .compactMap { account -> QuietItem? in
                let followsYou = followers.contains(account.username)
                guard includeMutuals || !followsYou else { return nil }
                if let followed = account.since, followed >= cutoff { return nil }
                let seen = activity.lastSeen[account.username]
                if let seen, seen.date >= cutoff { return nil }
                return QuietItem(username: account.username, name: account.name, followedAt: account.since, lastSeen: seen, followsYou: followsYou)
            }
            .sorted { ($0.quietSince ?? .distantPast, $0.username) < ($1.quietSince ?? .distantPast, $1.username) }
    }
}

public enum Analyzer {
    /// How many of the nearest follows by date are compared when judging a
    /// follow's period.
    static let neighborhood = 30

    /// Analyses the latest of `snapshots`, using the earlier ones for history.
    /// All snapshots must belong to the same account.
    public static func report(for snapshots: [Snapshot]) -> Report? {
        let ordered = snapshots.sorted(by: Snapshot.chronological)
        guard let latest = ordered.last else { return nil }

        let followers = Set(latest.followers.map(\.username))
        let notFollowingBack = latest.following.filter { !followers.contains($0.username) }
        let mutualCount = latest.following.count - notFollowingBack.count
        let history = formerFollowers(ordered)
        let eraRates = periodMutualRates(following: latest.following, followers: followers)
        let overallRate = latest.following.isEmpty ? 0 : Double(mutualCount) / Double(latest.following.count)
        // A follow period counts as "friends" when at least half of its follows are
        // mutual and that is 20 points above the account's overall rate. Someone
        // who follows few creators is mutual everywhere, and the signal would mean
        // nothing for them.
        let friendsThreshold = max(0.5, overallRate + 0.2)
        let pending = Set(latest.pendingRequests.map(\.username))

        let items = notFollowingBack.map { account -> ReportItem in
            var signals: [Signal] = []
            if let seen = history[account.username] {
                signals.append(.unfollowedYou(lastSeen: seen.lastSeen, goneBy: seen.goneBy))
                if seen.formerName != account.username {
                    signals.append(.renamed(from: seen.formerName))
                }
            }
            if latest.closeFriends.contains(account.username) { signals.append(.closeFriend) }
            if latest.receivedRequests.contains(account.username) { signals.append(.wantsToFollowYou) }
            if latest.hiddenStoryFrom.contains(account.username) { signals.append(.hiddenFromStory) }
            if latest.sentRequests.contains(account.username) { signals.append(.requestedToFollow) }
            if pending.contains(account.username) { signals.append(.requestPending) }
            if let rate = eraRates[account.username], rate >= friendsThreshold {
                signals.append(.followedWithFriends(rate: rate))
            }

            let group: ReportItem.Group
            if history[account.username] != nil {
                group = .unfollowedYou
            } else if signals.isEmpty {
                group = .noSignal
            } else {
                group = .likelyPersonal
            }
            return ReportItem(username: account.username, name: account.name, followedAt: account.since, signals: signals, group: group)
        }

        let previous = ordered.count > 1 ? ordered[ordered.count - 2] : nil
        return Report(
            snapshot: latest,
            previous: previous,
            mutualCount: mutualCount,
            items: items.sorted(by: reportOrder),
            pendingRequests: latest.pendingRequests.sorted { ($0.since ?? .distantFuture) < ($1.since ?? .distantFuture) },
            changes: previous.map { diff(from: $0, to: latest) },
            activity: mergedActivity(ordered)
        )
    }

    /// Combines the activity of every export. Older exports still count: a
    /// like recorded in March stays the latest sign of an account even if a
    /// later export's viewed-posts log no longer reaches back that far.
    static func mergedActivity(_ snapshots: [Snapshot]) -> ActivityOverview? {
        var lastSeen: [String: Activity] = [:]
        var coverage: [ActivityKind: ActivityCoverage] = [:]
        for summary in snapshots.compactMap(\.activity) {
            for (username, activity) in summary.lastSeen where lastSeen[username].map({ $0.date < activity.date }) ?? true {
                lastSeen[username] = activity
            }
            for span in summary.coverage {
                guard var merged = coverage[span.kind] else {
                    coverage[span.kind] = span
                    continue
                }
                merged.first = min(merged.first, span.first)
                merged.last = max(merged.last, span.last)
                merged.count = max(merged.count, span.count)
                coverage[span.kind] = merged
            }
        }
        guard !coverage.isEmpty else { return nil }
        return ActivityOverview(lastSeen: lastSeen, coverage: ActivityKind.allCases.compactMap { coverage[$0] })
    }

    /// Unfollows are listed newest first, personal accounts by strength of
    /// evidence, and the rest by most recent follow.
    private static func reportOrder(_ lhs: ReportItem, _ rhs: ReportItem) -> Bool {
        if lhs.group != rhs.group { return lhs.group < rhs.group }
        switch lhs.group {
        case .unfollowedYou:
            if lhs.goneBy != rhs.goneBy { return (lhs.goneBy ?? .distantPast) > (rhs.goneBy ?? .distantPast) }
        case .likelyPersonal:
            if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
        case .noSignal:
            break
        }
        if lhs.followedAt != rhs.followedAt { return (lhs.followedAt ?? .distantPast) > (rhs.followedAt ?? .distantPast) }
        return lhs.username < rhs.username
    }

    // MARK: - History

    struct FormerFollower {
        let lastSeen: Date
        let goneBy: Date
        /// The username they had in the last export where they followed you.
        let formerName: String
    }

    /// Everyone who followed you in an earlier export, keyed by their username
    /// in the latest export, with the last export where they still followed you.
    static func formerFollowers(_ ordered: [Snapshot]) -> [String: FormerFollower] {
        guard ordered.count > 1 else { return [:] }

        // renameSteps[k] maps usernames in ordered[k] to usernames in ordered[k + 1].
        var renameSteps: [[String: String]] = []
        for k in 0..<(ordered.count - 1) {
            var step = renames(from: ordered[k].following, to: ordered[k + 1].following)
            for (old, new) in renames(from: ordered[k].followers, to: ordered[k + 1].followers) where step[old] == nil {
                step[old] = new
            }
            renameSteps.append(step)
        }
        func currentName(_ name: String, from index: Int) -> String {
            renameSteps[index...].reduce(name) { $1[$0] ?? $0 }
        }

        var result: [String: FormerFollower] = [:]
        for k in 0..<(ordered.count - 1) {
            for follower in ordered[k].followers {
                result[currentName(follower.username, from: k)] = FormerFollower(
                    lastSeen: ordered[k].takenAt,
                    goneBy: ordered[k + 1].takenAt,
                    formerName: follower.username
                )
            }
        }
        // Keep only people who don't follow you in the latest export.
        let current = Set(ordered[ordered.count - 1].followers.map(\.username))
        return result.filter { !current.contains($0.key) }
    }

    /// Pairs accounts that disappeared from a list with accounts that appeared
    /// in it, when both carry the same follow time (or Meta id). A follow time
    /// survives a username change, so a match means one account renamed.
    static func renames(from old: [Account], to new: [Account]) -> [String: String] {
        let oldNames = Set(old.map(\.username))
        let newNames = Set(new.map(\.username))
        let gone = old.filter { !newNames.contains($0.username) }
        let added = new.filter { !oldNames.contains($0.username) }
        guard !gone.isEmpty, !added.isEmpty else { return [:] }

        var result: [String: String] = [:]

        // Some exports repeat the owner's id on every entry, so ids are used
        // only when they tell entries apart.
        let ids = new.compactMap(\.fbid)
        if ids.count == new.count, Set(ids).count == ids.count {
            let addedByID = Dictionary(added.compactMap { a in a.fbid.map { ($0, a.username) } }, uniquingKeysWith: { first, _ in first })
            for account in gone {
                if let id = account.fbid, let match = addedByID[id] { result[account.username] = match }
            }
        }

        let goneByTime = Dictionary(grouping: gone.filter { $0.since != nil }, by: { $0.since! })
        let addedByTime = Dictionary(grouping: added.filter { $0.since != nil }, by: { $0.since! })
        for (time, accounts) in goneByTime where accounts.count == 1 {
            guard let matches = addedByTime[time], matches.count == 1, result[accounts[0].username] == nil else { continue }
            result[accounts[0].username] = matches[0].username
        }
        return result
    }

    // MARK: - Follow periods

    /// For each account you follow that doesn't follow you back, the share of
    /// your nearest follows by date that do follow you back.
    static func periodMutualRates(following: [Account], followers: Set<String>) -> [String: Double] {
        let dated = following.filter { $0.since != nil }.sorted { $0.since! < $1.since! }
        guard dated.count >= 20 else { return [:] }
        let times = dated.map { $0.since!.timeIntervalSince1970 }
        let mutual = dated.map { followers.contains($0.username) }

        var rates: [String: Double] = [:]
        for index in dated.indices where !mutual[index] {
            var low = index - 1
            var high = index + 1
            var compared = 0
            var hits = 0
            while compared < neighborhood, low >= 0 || high < dated.count {
                let takeLow: Bool
                if low < 0 {
                    takeLow = false
                } else if high >= dated.count {
                    takeLow = true
                } else {
                    takeLow = times[index] - times[low] <= times[high] - times[index]
                }
                let neighbor = takeLow ? low : high
                if mutual[neighbor] { hits += 1 }
                compared += 1
                if takeLow { low -= 1 } else { high += 1 }
            }
            rates[dated[index].username] = Double(hits) / Double(compared)
        }
        return rates
    }

    // MARK: - Diff

    public static func diff(from old: Snapshot, to new: Snapshot) -> SnapshotDiff {
        let followerRenames = renames(from: old.followers, to: new.followers)
        let followingRenames = renames(from: old.following, to: new.following)

        func changes(_ before: [Account], _ after: [Account], _ renamed: [String: String]) -> (lost: [Account], gained: [Account]) {
            let beforeNames = Set(before.map(\.username))
            let afterNames = Set(after.map(\.username))
            let renamedTo = Set(renamed.values)
            return (
                before.filter { !afterNames.contains($0.username) && renamed[$0.username] == nil },
                after.filter { !beforeNames.contains($0.username) && !renamedTo.contains($0.username) }
            )
        }

        let followerChanges = changes(old.followers, new.followers, followerRenames)
        let followingChanges = changes(old.following, new.following, followingRenames)
        var renames = Set<SnapshotDiff.Rename>()
        for (old, new) in followerRenames.merging(followingRenames, uniquingKeysWith: { first, _ in first }) {
            renames.insert(SnapshotDiff.Rename(old: old, new: new))
        }
        return SnapshotDiff(
            lostFollowers: followerChanges.lost,
            newFollowers: followerChanges.gained,
            unfollowedByYou: followingChanges.lost,
            followedByYou: followingChanges.gained,
            renames: renames.sorted { $0.new < $1.new }
        )
    }
}
