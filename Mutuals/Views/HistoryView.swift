import MutualsCore
import SwiftUI

struct HistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var pendingDeletion: Snapshot?

    var body: some View {
        let snapshots = store.currentSnapshots
        List {
            Section {
                ForEach(snapshots.indices.reversed(), id: \.self) { index in
                    let snapshot = snapshots[index]
                    NavigationLink(value: Route.snapshot(snapshot.id)) {
                        HistoryRow(snapshot: snapshot, previous: index > 0 ? snapshots[index - 1] : nil)
                    }
                    .swipeActions {
                        if !snapshot.isSample {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = snapshot }
                        }
                    }
                }
            } footer: {
                Text("Each export is compared with the one before it. Deleting an export takes it out of those comparisons.")
            }
        }
        .navigationTitle("Exports")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete the export of \(pendingDeletion?.takenAt.mediumDay ?? "")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { snapshot in
            Button("Delete Export", role: .destructive) { store.delete(snapshot) }
        }
    }
}

private struct HistoryRow: View {
    let snapshot: Snapshot
    let previous: Snapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snapshot.takenAt.mediumDay)
                .font(.body.weight(.medium))
            Text("\(snapshot.followers.count.formatted()) followers · \(snapshot.following.count.formatted()) following")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Group {
                if let previous {
                    let diff = Analyzer.diff(from: previous, to: snapshot)
                    Text("\(peopleCount(diff.lostFollowers.count)) unfollowed you, \(diff.newFollowers.count.formatted()) new")
                } else {
                    Text("First export")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

struct SnapshotDetailView: View {
    @Environment(AppStore.self) private var store
    let id: UUID

    var body: some View {
        let snapshots = store.currentSnapshots
        if let index = snapshots.firstIndex(where: { $0.id == id }) {
            let snapshot = snapshots[index]
            let previous = index > 0 ? snapshots[index - 1] : nil
            List {
                Section {
                    LabeledContent("Followers", value: snapshot.followers.count.formatted())
                    LabeledContent("Following", value: snapshot.following.count.formatted())
                    LabeledContent("Imported", value: snapshot.importedAt.mediumDay)
                    if let source = snapshot.sourceName {
                        LabeledContent("File", value: source)
                    }
                }
                if let previous {
                    let diff = Analyzer.diff(from: previous, to: snapshot)
                    accounts("Stopped following you", diff.lostFollowers)
                    accounts("Started following you", diff.newFollowers)
                    accounts("You unfollowed", diff.unfollowedByYou)
                    accounts("You followed", diff.followedByYou)
                    if !diff.renames.isEmpty {
                        Section("Changed username") {
                            ForEach(diff.renames, id: \.self) { rename in
                                Text(verbatim: "@\(rename.old) → @\(rename.new)")
                            }
                        }
                    }
                } else {
                    Section {
                        Text("This is the first export, so there's nothing to compare it with.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(snapshot.takenAt.mediumDay)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Export deleted", systemImage: "tray")
        }
    }

    @ViewBuilder private func accounts(_ title: String, _ accounts: [Account]) -> some View {
        if !accounts.isEmpty {
            Section("\(title) (\(accounts.count))") {
                ForEach(accounts, id: \.username) { UsernameRow(account: $0, detail: $0.name) }
            }
        }
    }
}
