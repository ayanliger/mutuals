import MutualsCore
import SwiftUI
import UIKit

struct AccountRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let username: String
    let name: String?
    let reason: String?
    /// Unfollows are the one reason drawn in the accent color.
    let highlightsReason: Bool
    let followedAt: Date?

    init(item: ReportItem) {
        username = item.username
        name = item.name
        reason = item.reason
        highlightsReason = item.group == .unfollowedYou
        followedAt = item.followedAt
    }

    init(quiet: QuietItem) {
        username = quiet.username
        name = quiet.name
        reason = quiet.reason
        highlightsReason = false
        followedAt = quiet.followedAt
    }

    var body: some View {
        let decision = store.decision(for: username)
        Button {
            store.open(username, with: openURL, askOnReturn: decision == nil)
        } label: {
            // Concrete colors: inside a button, the hierarchical .primary and
            // .secondary styles resolve to the tint.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "@\(username)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                    if let name, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    if let reason {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(highlightsReason ? Color.accentColor : Color.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let followedAt {
                    Text(followedAt.monthYear)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Color.secondary)
                        .accessibilityLabel("Followed \(followedAt.monthYear)")
                }
            }
            .contentShape(.rect)
        }
        .accessibilityHint("Opens the profile in Instagram")
        .swipeActions(edge: .trailing) {
            if decision == nil {
                // Swipe labels are always white, which needs the darker green in both modes.
                Button("Unfollowed", systemImage: "checkmark") { store.setDecision(.unfollowed, for: username) }
                    .tint(Color("AccentDeep"))
            } else {
                Button("Undo", systemImage: "arrow.uturn.backward") { store.setDecision(nil, for: username) }
            }
        }
        .swipeActions(edge: .leading) {
            if decision == nil {
                Button("Keep", systemImage: "pin") { store.setDecision(.keep, for: username) }
                    .tint(.gray)
            }
        }
        .contextMenu {
            Button("Open in Instagram", systemImage: "arrow.up.forward.app") {
                store.open(username, with: openURL, askOnReturn: decision == nil)
            }
            Button("Copy Username", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = username
            }
            Divider()
            if decision == nil {
                Button("Keep Following", systemImage: "pin") { store.setDecision(.keep, for: username) }
                Button("Mark as Unfollowed", systemImage: "checkmark.circle") { store.setDecision(.unfollowed, for: username) }
            } else {
                Button("Move Back to Lists", systemImage: "arrow.uturn.backward") { store.setDecision(nil, for: username) }
            }
        }
    }
}

/// A plain account row for lists that aren't part of the report.
struct UsernameRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let account: Account
    var detail: String?

    var body: some View {
        Button {
            store.open(account.username, with: openURL, askOnReturn: false)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "@\(account.username)")
                    .foregroundStyle(Color.primary)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .contextMenu {
            Button("Copy Username", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = account.username
            }
        }
    }
}
