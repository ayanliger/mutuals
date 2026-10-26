import MutualsCore
import SwiftUI
import UIKit

struct AccountRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let item: ReportItem

    var body: some View {
        let decision = store.decision(for: item.username)
        Button {
            store.open(item.username, with: openURL, askOnReturn: decision == nil)
        } label: {
            // Concrete colors: inside a button, the hierarchical .primary and
            // .secondary styles resolve to the tint.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "@\(item.username)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                    if let name = item.name, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                    if let reason = item.reason {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(item.group == .unfollowedYou ? Color.accentColor : Color.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let followedAt = item.followedAt {
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
                Button("Unfollowed", systemImage: "checkmark") { store.setDecision(.unfollowed, for: item.username) }
                    .tint(Color("AccentDeep"))
            } else {
                Button("Undo", systemImage: "arrow.uturn.backward") { store.setDecision(nil, for: item.username) }
            }
        }
        .swipeActions(edge: .leading) {
            if decision == nil {
                Button("Keep", systemImage: "pin") { store.setDecision(.keep, for: item.username) }
                    .tint(.gray)
            }
        }
        .contextMenu {
            Button("Open in Instagram", systemImage: "arrow.up.forward.app") {
                store.open(item.username, with: openURL, askOnReturn: decision == nil)
            }
            Button("Copy Username", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = item.username
            }
            Divider()
            if decision == nil {
                Button("Keep Following", systemImage: "pin") { store.setDecision(.keep, for: item.username) }
                Button("Mark as Unfollowed", systemImage: "checkmark.circle") { store.setDecision(.unfollowed, for: item.username) }
            } else {
                Button("Move Back to Lists", systemImage: "arrow.uturn.backward") { store.setDecision(nil, for: item.username) }
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
