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
