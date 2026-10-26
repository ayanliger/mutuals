import Foundation
import MutualsCore

extension Date {
    /// "25 Oct 2026", ordered for the device's locale.
    var mediumDay: String {
        formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// "25 Oct" this year, "25 Oct 2025" otherwise.
    var shortDay: String {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year)
            ? formatted(.dateTime.day().month(.abbreviated))
            : mediumDay
    }

    /// "Oct 2026"
    var monthYear: String {
        formatted(.dateTime.month(.abbreviated).year())
    }
}

extension Signal {
    var label: String {
        switch self {
        case .unfollowedYou(let lastSeen, _):
            "Unfollowed you after \(lastSeen.shortDay)"
        case .renamed(let old):
            "was @\(old)"
        case .closeFriend:
            "On your close friends list"
        case .hiddenFromStory:
            "Hidden from your stories"
        case .requestPending:
            "Your follow request is pending"
        case .requestedToFollow:
            "Private account you asked to follow"
        case .wantsToFollowYou:
            "Asked to follow you"
        case .followedWithFriends(let rate):
            "\(rate.formatted(.percent.precision(.fractionLength(0)))) of your follows from then are mutual"
        }
    }
}

extension ReportItem {
    /// The signals as one line. The follow-period estimate is left out when
    /// anything firmer explains the account.
    var reason: String? {
        let firm = signals.filter { if case .followedWithFriends = $0 { false } else { true } }
        let shown = firm.isEmpty ? signals : firm
        return shown.isEmpty ? nil : shown.map(\.label).joined(separator: " · ")
    }
}

extension ActivityKind {
    /// "liked a post"
    var action: String {
        switch self {
        case .likedPost: "liked a post"
        case .comment: "commented"
        case .storyLike: "liked a story"
        case .saved: "saved a post"
        case .viewedPost: "viewed a post"
        case .viewedVideo: "watched a video"
        }
    }

    /// "likes", as in "your likes since 2014"
    var logName: String {
        switch self {
        case .likedPost: "likes"
        case .comment: "comments"
        case .storyLike: "story likes"
        case .saved: "saves"
        case .viewedPost: "viewed posts"
        case .viewedVideo: "watched videos"
        }
    }
}

extension QuietItem {
    var reason: String {
        var parts = [lastSeen.map { "Last seen: \($0.kind.action), \($0.date.monthYear)" } ?? "Nothing on record"]
        if followsYou { parts.append("Follows you") }
        return parts.joined(separator: " · ")
    }
}

/// Settings for the Quiet list, shared by the overview and the list itself.
enum QuietSettings {
    static let monthsKey = "quietMonths"
    static let mutualsKey = "quietIncludesMutuals"
    static let choices = [6, 12, 24, 36]

    /// "a year", "2 years", "6 months"
    static func period(_ months: Int) -> String {
        if months == 12 { return "a year" }
        return months % 12 == 0 ? "\(months / 12) years" : "\(months) months"
    }
}

/// "Based on your likes since May 2014, comments since Feb 2015 and viewed posts since Jul 2026."
func coverageText(_ coverage: [ActivityCoverage]) -> String {
    let parts = coverage.map { "\($0.kind.logName) since \($0.first.monthYear)" }
    return "Based on your \(ListFormatter.localizedString(byJoining: parts))."
}
