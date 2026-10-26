import MutualsCore
import SwiftUI

enum ListSource: Hashable {
    case group(ReportItem.Group)
    case decided(Decision.Kind)

    var title: String {
        switch self {
        case .group(.unfollowedYou): "Unfollowed you"
        case .group(.likelyPersonal): "Likely personal"
        case .group(.noSignal): "No personal signal"
        case .decided(.keep): "Kept"
        case .decided(.unfollowed): "Marked as unfollowed"
        }
    }

    var footer: String? {
        switch self {
        case .decided(.keep):
            "Accounts you chose to keep following. They stay out of the other lists."
        case .decided(.unfollowed):
            "The next export settles these. Accounts you really unfollowed drop off, and any still in your following list come back."
        default:
            nil
        }
    }
}

struct AccountListView: View {
    @Environment(AppStore.self) private var store
    let source: ListSource
    @State private var query = ""
    @State private var order = Order.suggested

    enum Order: String, CaseIterable, Identifiable {
        case suggested = "Suggested"
        case recent = "Recently Followed"
        case oldest = "Oldest Follows"
        case username = "Username"

        var id: Self { self }
    }

    private var items: [ReportItem] {
        let all = switch source {
        case .group(let group): store.items(in: group)
        case .decided(let kind): store.items(decided: kind)
        }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = needle.isEmpty ? all : all.filter {
            $0.username.contains(needle) || ($0.name?.lowercased().contains(needle) ?? false)
        }
        return switch order {
        case .suggested: matching
        case .recent: matching.sorted { ($0.followedAt ?? .distantPast) > ($1.followedAt ?? .distantPast) }
        case .oldest: matching.sorted { ($0.followedAt ?? .distantFuture) < ($1.followedAt ?? .distantFuture) }
        case .username: matching.sorted { $0.username < $1.username }
        }
    }

    var body: some View {
        let items = items
        List {
            Section {
                ForEach(items) { AccountRow(item: $0) }
            } footer: {
                if let footer = source.footer { Text(footer) }
            }
        }
        .overlay {
            if items.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Nothing here", systemImage: "person.crop.circle.badge.checkmark")
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, prompt: "Username or name")
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Order", selection: $order) {
                        ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    Label("Order", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }
}

struct RequestsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let requests = store.report?.pendingRequests ?? []
        List {
            if !requests.isEmpty {
                Section {
                    ForEach(requests, id: \.username) { account in
                        UsernameRow(account: account, detail: account.since.map { "Requested \($0.mediumDay)" })
                    }
                } footer: {
                    Text("Follow requests you sent that were never accepted. Open one in Instagram and tap Requested to cancel it.")
                }
            }
        }
        .overlay {
            if requests.isEmpty {
                ContentUnavailableView(
                    "No pending requests",
                    systemImage: "person.crop.circle.badge.clock",
                    description: Text("Follow requests you sent that were never accepted show up here.")
                )
            }
        }
        .navigationTitle("Requests you sent")
        .navigationBarTitleDisplayMode(.inline)
    }
}
