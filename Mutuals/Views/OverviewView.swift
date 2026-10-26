import MutualsCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppStore.self) private var store
    let report: Report

    /// Rows shown per section before "Show all".
    private var previewCount: Int {
        #if DEBUG
        // `-preview <n>` shortens the sections so screenshots reach the bottom.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-preview"), index + 1 < arguments.count, let count = Int(arguments[index + 1]) {
            return count
        }
        #endif
        return 8
    }

    var body: some View {
        List {
            if report.snapshot.isSample {
                Section {
                    LabeledContent("Showing sample data") {
                        Button("Clear") { store.removeSample() }
                    }
                }
            }

            Section {
                SummaryView(report: report)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
            }

            unfollowedSection
            personalSection

            Section {
                link("No personal signal", count: store.items(in: .noSignal).count, to: .list(.group(.noSignal)))
            } footer: {
                Text("Mostly creators, brands and public figures. In any list, swipe left to mark an account as unfollowed or right to keep it.")
            }

            Section {
                link("Kept", count: store.items(decided: .keep).count, to: .list(.decided(.keep)))
                link("Marked as unfollowed", count: store.items(decided: .unfollowed).count, to: .list(.decided(.unfollowed)))
                link("Requests you sent", count: report.pendingRequests.count, to: .requests)
            }

            Section {
                link("Exports", count: store.currentSnapshots.count, to: .history)
                NavigationLink("About Mutuals", value: Route.about)
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import", systemImage: "square.and.arrow.down") { store.isImporterPresented = true }
            }
            if store.owners.count > 1 {
                ToolbarItem(placement: .topBarLeading) {
                    AccountMenu()
                }
            }
        }
    }

    private var title: String {
        if report.snapshot.isSample { return "Sample" }
        return report.snapshot.owner.map { "@\($0)" } ?? "Mutuals"
    }

    @ViewBuilder private var unfollowedSection: some View {
        let items = store.items(in: .unfollowedYou)
        Section {
            if report.previous == nil {
                Text("Import another export in a week or two. Mutuals will compare it with this one and list everyone who stopped following you.")
                    .foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("Nobody you follow has unfollowed you since \(currentFirstExportDate).")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(previewCount)) { AccountRow(item: $0) }
                if items.count > previewCount {
                    NavigationLink("Show all \(items.count)", value: Route.list(.group(.unfollowedYou)))
                }
            }
        } header: {
            Text("Unfollowed you")
        } footer: {
            if !items.isEmpty {
                Text("They followed you in an earlier export and don't in this one. You still follow them.")
            }
        }
    }

    @ViewBuilder private var personalSection: some View {
        let items = store.items(in: .likelyPersonal)
        Section {
            if items.isEmpty {
                Text("No other account you follow shows signs of being a person you know.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(previewCount)) { AccountRow(item: $0) }
                if items.count > previewCount {
                    NavigationLink("Show all \(items.count)", value: Route.list(.group(.likelyPersonal)))
                }
            }
        } header: {
            Text("Likely personal")
        } footer: {
            Text("Close friends, private accounts, people who asked to follow you, and accounts you followed at a time when most of your follows were mutual.")
        }
    }

    private var currentFirstExportDate: String {
        store.currentSnapshots.first?.takenAt.mediumDay ?? ""
    }

    private func link(_ title: String, count: Int, to route: Route) -> some View {
        NavigationLink(value: route) {
            LabeledContent(title, value: count.formatted())
        }
    }
}

/// The headline numbers, set as a sentence rather than as tiles.
struct SummaryView: View {
    let report: Report

    var body: some View {
        let count = report.items.count
        VStack(alignment: .leading, spacing: 6) {
            Text("Export of \(report.snapshot.takenAt.mediumDay)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(count.formatted())
                .font(.system(size: 56, weight: .semibold, design: .serif))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("of the \(report.followingCount.formatted()) accounts you follow \(count == 1 ? "doesn't" : "don't") follow you back.")
                .font(.title3)
            Group {
                Text("\(report.followersCount.formatted()) followers, \(report.mutualCount.formatted()) of them mutual.")
                if let changes = report.changes, let previous = report.previous {
                    Text("Since \(previous.takenAt.mediumDay): \(peopleCount(changes.lostFollowers.count)) stopped following you and \(changes.newFollowers.count.formatted()) started.")
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Switches between exported accounts when there is more than one.
struct AccountMenu: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Menu {
            Picker("Account", selection: Binding(get: { store.currentOwner }, set: { store.selectedOwner = $0 })) {
                ForEach(store.owners, id: \.self) { owner in
                    Text(owner.isEmpty ? "Unknown account" : "@\(owner)").tag(Optional(owner))
                }
            }
        } label: {
            Label("Account", systemImage: "person.2")
        }
    }
}
