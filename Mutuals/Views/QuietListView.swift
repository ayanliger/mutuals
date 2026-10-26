import MutualsCore
import SwiftUI

/// Accounts you follow whose content you haven't seen or interacted with
/// since a cut-off.
struct QuietListView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(QuietSettings.monthsKey) private var months = 12
    @AppStorage(QuietSettings.mutualsKey) private var includeMutuals = false
    @State private var query = ""

    var body: some View {
        Group {
            if let activity = store.report?.activity {
                list(activity)
            } else {
                ActivityMissingView()
            }
        }
        .navigationTitle("Quiet accounts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func list(_ activity: ActivityOverview) -> some View {
        let all = store.quietItems(months: months, includeMutuals: includeMutuals)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let items = needle.isEmpty ? all : all.filter {
            $0.username.contains(needle) || ($0.name?.lowercased().contains(needle) ?? false)
        }
        return List {
            Section {
                ForEach(items) { AccountRow(quiet: $0) }
            } header: {
                Text("\(all.count.formatted()) quiet for over \(QuietSettings.period(months))")
            } footer: {
                Text("\(coverageText(activity.coverage)) Instagram's export can't say whether an account stopped posting or you scroll past it. Accounts you followed within the period aren't listed.")
            }
        }
        .overlay {
            if items.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("Nothing quiet", systemImage: "checkmark.circle", description: Text("Every account you follow showed up in your activity in the last \(QuietSettings.period(months))."))
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, prompt: "Username or name")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Quiet for", selection: $months) {
                        ForEach(QuietSettings.choices, id: \.self) { Text("Over \(QuietSettings.period($0))").tag($0) }
                    }
                    Toggle("Include mutuals", isOn: $includeMutuals)
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
    }
}

/// Shown until an export with activity logs is imported.
struct ActivityMissingView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Section {
                Text("The Quiet list needs your activity from Instagram: likes, comments, saves, story likes and the posts you viewed. Your exports so far only have followers and following.")
                    .foregroundStyle(.secondary)
            }
            Section("Get an export with activity") {
                ExportSteps()
                Link(destination: Instagram.exportPage) {
                    Label("Open Export Your Information", systemImage: "arrow.up.forward.square")
                }
            }
            Section {
                Button("Import Instagram Export", systemImage: "square.and.arrow.down") { store.isImporterPresented = true }
            }
        }
    }
}
