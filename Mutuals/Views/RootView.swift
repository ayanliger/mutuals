import MutualsCore
import SwiftUI
import UniformTypeIdentifiers

enum Route: Hashable {
    case list(ListSource)
    case requests
    case history
    case snapshot(UUID)
    case about
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var leftForInstagram = false
    @State private var askingAbout: String?
    @State private var path: [Route] = []

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .list(let source): AccountListView(source: source)
                    case .requests: RequestsView()
                    case .history: HistoryView()
                    case .snapshot(let id): SnapshotDetailView(id: id)
                    case .about: AboutView()
                    }
                }
        }
        .fileImporter(
            isPresented: $store.isImporterPresented,
            allowedContentTypes: [.zip, .folder, .json, .html],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): store.importFiles(urls)
            case .failure(let error): store.alert = AppAlert(error)
            }
        }
        .overlay {
            if store.isImporting {
                ProgressView("Reading export")
                    .padding(24)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .alert(
            store.alert?.title ?? "",
            isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } }),
            presenting: store.alert
        ) { _ in
            Button("OK") {}
        } message: { alert in
            Text(alert.message)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background where store.awaitingReturn != nil:
                leftForInstagram = true
            case .active where leftForInstagram:
                leftForInstagram = false
                askingAbout = store.awaitingReturn
                store.awaitingReturn = nil
            case .active:
                // Back without leaving, as when the "Open in Instagram?" prompt is cancelled.
                store.awaitingReturn = nil
            default:
                break
            }
        }
        .confirmationDialog(
            "Did you unfollow @\(askingAbout ?? "")?",
            isPresented: Binding(get: { askingAbout != nil }, set: { if !$0 { askingAbout = nil } }),
            titleVisibility: .visible,
            presenting: askingAbout
        ) { username in
            Button("Unfollowed") { store.setDecision(.unfollowed, for: username) }
            Button("Keep Following") { store.setDecision(.keep, for: username) }
            Button("Not Now", role: .cancel) {}
        }
        #if DEBUG
        .onChange(of: store.report?.snapshot.id) {
            // `-route <name>` opens a screen at launch, for screenshots.
            let arguments = ProcessInfo.processInfo.arguments
            guard path.isEmpty, let index = arguments.firstIndex(of: "-route"), index + 1 < arguments.count else { return }
            let routes: [String: Route] = [
                "unfollowed": .list(.group(.unfollowedYou)), "personal": .list(.group(.likelyPersonal)),
                "rest": .list(.group(.noSignal)), "kept": .list(.decided(.keep)), "requests": .requests,
                "history": .history, "about": .about,
            ]
            if arguments[index + 1] == "snapshot", let id = store.currentSnapshots.last?.id {
                path = [.history, .snapshot(id)]
            } else if let route = routes[arguments[index + 1]] {
                path = [route]
            }
        }
        #endif
    }

    @ViewBuilder private var content: some View {
        if !store.isLoaded {
            ProgressView()
        } else if store.currentSnapshots.isEmpty {
            WelcomeView()
        } else if let report = store.report, store.currentSnapshots.contains(where: { $0.id == report.snapshot.id }) {
            OverviewView(report: report)
        } else {
            ProgressView()
        }
    }
}
