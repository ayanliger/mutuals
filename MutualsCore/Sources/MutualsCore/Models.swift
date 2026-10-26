import Foundation

/// One account in a followers or following list.
public struct Account: Codable, Hashable, Sendable {
    public var username: String
    /// Display name. Exports from before August 2026 do not include it.
    public var name: String?
    /// When the relationship started: when you followed them, or when they followed you.
    public var since: Date?
    /// Meta's account id, when the export includes one.
    public var fbid: String?

    public init(username: String, name: String? = nil, since: Date? = nil, fbid: String? = nil) {
        self.username = username
        self.name = name
        self.since = since
        self.fbid = fbid
    }
}

/// The relationship lists from one Instagram export, frozen at the time it was made.
public struct Snapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// The exported account's username, from the archive's file name.
    public var owner: String?
    /// When Instagram generated the export.
    public var takenAt: Date
    public var importedAt: Date
    public var sourceName: String?
    public var followers: [Account]
    public var following: [Account]
    public var closeFriends: Set<String>
    public var hiddenStoryFrom: Set<String>
    /// Follow requests you sent that are still waiting for an answer.
    public var pendingRequests: [Account]
    /// Accounts you sent a follow request to at some point, from `recent_follow_requests`.
    public var sentRequests: Set<String>
    /// Requests to follow you that are waiting for your approval.
    public var receivedRequests: Set<String>
    /// Accounts you unfollowed in the weeks before the export.
    public var recentlyUnfollowed: [Account]
    /// True only for the built-in demo data, which is never saved.
    public var isSample: Bool
    /// True when the lists came from the HTML export, which has no follow dates.
    public var fromHTML: Bool
    /// Your activity toward the accounts you followed, when the export
    /// included it. Optional so snapshots saved before it existed still load.
    public var activity: ActivitySummary?

    public init(
        id: UUID = UUID(),
        owner: String? = nil,
        takenAt: Date,
        importedAt: Date = Date(),
        sourceName: String? = nil,
        followers: [Account],
        following: [Account],
        closeFriends: Set<String> = [],
        hiddenStoryFrom: Set<String> = [],
        pendingRequests: [Account] = [],
        sentRequests: Set<String> = [],
        receivedRequests: Set<String> = [],
        recentlyUnfollowed: [Account] = [],
        isSample: Bool = false,
        fromHTML: Bool = false,
        activity: ActivitySummary? = nil
    ) {
        self.id = id
        self.owner = owner
        self.takenAt = takenAt
        self.importedAt = importedAt
        self.sourceName = sourceName
        self.followers = followers
        self.following = following
        self.closeFriends = closeFriends
        self.hiddenStoryFrom = hiddenStoryFrom
        self.pendingRequests = pendingRequests
        self.sentRequests = sentRequests
        self.receivedRequests = receivedRequests
        self.recentlyUnfollowed = recentlyUnfollowed
        self.isSample = isSample
        self.fromHTML = fromHTML
        self.activity = activity
    }

    /// Orders snapshots by export time, then import time for exports made the same moment.
    public static func chronological(_ lhs: Snapshot, _ rhs: Snapshot) -> Bool {
        (lhs.takenAt, lhs.importedAt) < (rhs.takenAt, rhs.importedAt)
    }

    /// Share of usernames the two snapshots' following lists have in common
    /// (Jaccard index). Used to tell whether two exports belong to one account.
    public func followingOverlap(with other: Snapshot) -> Double {
        let mine = Set(following.map(\.username))
        let theirs = Set(other.following.map(\.username))
        let union = mine.union(theirs).count
        return union == 0 ? 0 : Double(mine.intersection(theirs).count) / Double(union)
    }

    /// True when both snapshots hold the same lists, as with the same export imported twice.
    public func hasSameLists(as other: Snapshot) -> Bool {
        Set(followers.map(\.username)) == Set(other.followers.map(\.username))
            && Set(following.map(\.username)) == Set(other.following.map(\.username))
    }
}

/// The activity logs an export can include, each recording whose content you
/// interacted with and when.
public enum ActivityKind: String, Codable, CaseIterable, Sendable {
    case likedPost
    case comment
    case storyLike
    case saved
    case viewedPost
    case viewedVideo
}

/// The latest thing you did with an account's content.
public struct Activity: Codable, Hashable, Sendable {
    public var kind: ActivityKind
    public var date: Date

    public init(kind: ActivityKind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// The span one activity log covers. Instagram keeps some logs, such as
/// viewed posts, for a limited time, so "nothing on record" means less when
/// the span is short.
public struct ActivityCoverage: Codable, Hashable, Sendable {
    public var kind: ActivityKind
    public var first: Date
    public var last: Date
    public var count: Int

    public init(kind: ActivityKind, first: Date, last: Date, count: Int) {
        self.kind = kind
        self.first = first
        self.last = last
        self.count = count
    }
}

/// What an export says about your activity, reduced to one date per account.
/// Individual likes and views are not kept.
public struct ActivitySummary: Codable, Hashable, Sendable {
    /// Latest activity per account you followed when the export was made.
    public var lastSeen: [String: Activity]
    public var coverage: [ActivityCoverage]

    public init(lastSeen: [String: Activity], coverage: [ActivityCoverage]) {
        self.lastSeen = lastSeen
        self.coverage = coverage
    }
}
