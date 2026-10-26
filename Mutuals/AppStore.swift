import Foundation
import MutualsCore
import Observation
import SwiftUI

/// What the person decided about an account inside the app. Instagram never
/// learns about these; they only sort the lists here.
nonisolated struct Decision: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        /// Keep following; hide from the lists.
        case keep
        /// Unfollowed in Instagram; waiting for the next export to confirm.
        case unfollowed
    }

    var kind: Kind
    var date: Date
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(_ error: Error) {
        let localized = error as? LocalizedError
        title = localized?.errorDescription ?? "Couldn't import the export"
        message = localized?.recoverySuggestion ?? error.localizedDescription
    }
}

@Observable
final class AppStore {
    private(set) var snapshots: [Snapshot] = []
    private(set) var report: Report?
    private(set) var isLoaded = false
    private(set) var isImporting = false
    var isImporterPresented = false
    var alert: AppAlert?
    /// The username last opened in Instagram, so the app can ask what happened
    /// when the person comes back.
    var awaitingReturn: String?
    var selectedOwner: String? {
        didSet { refresh() }
    }

    /// Decisions per exported account, then per username.
    private var decisions: [String: [String: Decision]] = [:]
    private let storage = Storage()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    static let sampleOwner = "sample"

    init() {
        decisions = storage.loadDecisions()
        Task { await load() }
    }

    private func load() async {
        let storage = storage
        snapshots = await Task.detached(priority: .userInitiated) { storage.loadSnapshots() }.value
        isLoaded = true
        refresh()
        #if DEBUG
        handleLaunchArguments()
        #endif
    }

    // MARK: - Accounts

    static func ownerKey(_ snapshot: Snapshot) -> String {
        snapshot.owner ?? ""
    }

    /// Exported accounts, the most recently exported first.
    var owners: [String] {
        var seen = Set<String>()
        return snapshots.sorted(by: Snapshot.chronological).reversed().map(Self.ownerKey).filter { seen.insert($0).inserted }
    }

    var currentOwner: String? {
        if let selectedOwner, owners.contains(selectedOwner) { return selectedOwner }
        return owners.first
    }

    /// Snapshots of the account on screen, oldest first.
    var currentSnapshots: [Snapshot] {
        guard let owner = currentOwner else { return [] }
        return snapshots.filter { Self.ownerKey($0) == owner }.sorted(by: Snapshot.chronological)
    }

    var isShowingSample: Bool {
        currentOwner == Self.sampleOwner && snapshots.contains(where: \.isSample)
    }

    private func refresh() {
        let selection = currentSnapshots
        refreshTask?.cancel()
        refreshTask = Task {
            let report = await Task.detached(priority: .userInitiated) { Analyzer.report(for: selection) }.value
            guard !Task.isCancelled else { return }
            self.report = report
        }
    }

    // MARK: - Decisions

    func decision(for username: String) -> Decision? {
        decisions[currentOwner ?? ""]?[username]
    }

    func setDecision(_ kind: Decision.Kind?, for username: String) {
        let owner = currentOwner ?? ""
        decisions[owner, default: [:]][username] = kind.map { Decision(kind: $0, date: Date()) }
        saveDecisions()
    }

    /// Accounts in `group` that the person hasn't decided about yet.
    func items(in group: ReportItem.Group) -> [ReportItem] {
        report?.items(in: group).filter { decision(for: $0.username) == nil } ?? []
    }

    func items(decided kind: Decision.Kind) -> [ReportItem] {
        report?.items.filter { decision(for: $0.username)?.kind == kind } ?? []
    }

    /// Marks made before a newer export are settled by it: accounts that are
    /// gone from the following list are done, and accounts still there return
    /// to the lists. Keeps are permanent.
    private func settleDecisions(owner: String, upTo date: Date) {
        guard let marks = decisions[owner] else { return }
        decisions[owner] = marks.filter { $0.value.kind == .keep || $0.value.date > date }
        saveDecisions()
    }

    private func saveDecisions() {
        do {
            try storage.save(decisions: decisions.filter { $0.key != Self.sampleOwner })
        } catch {
            alert = AppAlert(title: "Couldn't save your changes", message: error.localizedDescription)
        }
    }

    // MARK: - Importing

    func importFiles(_ urls: [URL], removeAfterImport: Bool = false) {
        guard !urls.isEmpty, !isImporting else { return }
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
                    defer {
                        for (url, granted) in zip(urls, scoped) where granted {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    return try ExportReader.read(urls)
                }.value
                add(snapshot)
            } catch {
                alert = AppAlert(error)
            }
            if removeAfterImport {
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private func add(_ imported: Snapshot) {
        var snapshot = imported
        removeSample()

        if snapshot.owner == nil {
            // Loose JSON files carry no account name. Adopt the account whose
            // following list is mostly the same.
            snapshot.owner = snapshots
                .filter { $0.owner != nil && $0.followingOverlap(with: snapshot) > 0.6 }
                .max { $0.followingOverlap(with: snapshot) < $1.followingOverlap(with: snapshot) }?
                .owner
        }
        let owner = Self.ownerKey(snapshot)

        if let existing = snapshots.first(where: {
            Self.ownerKey($0) == owner && $0.hasSameLists(as: snapshot) && abs($0.takenAt.timeIntervalSince(snapshot.takenAt)) < 2 * 86_400
        }) {
            selectedOwner = owner
            alert = AppAlert(title: "Already imported", message: "The export from \(existing.takenAt.mediumDay) has the same lists.")
            return
        }

        if let named = snapshot.owner {
            for index in snapshots.indices where snapshots[index].owner == nil && snapshots[index].followingOverlap(with: snapshot) > 0.6 {
                snapshots[index].owner = named
                persist(snapshots[index])
            }
        }

        let sameAccount = snapshots.filter { Self.ownerKey($0) == owner }
        let previous = sameAccount.filter { Snapshot.chronological($0, snapshot) }.max(by: Snapshot.chronological)
        let isNewest = sameAccount.allSatisfy { Snapshot.chronological($0, snapshot) }
        snapshots.append(snapshot)
        persist(snapshot)
        if isNewest {
            settleDecisions(owner: owner, upTo: snapshot.takenAt)
        }
        selectedOwner = owner
        alert = importSummary(snapshot, previous: previous, isNewest: isNewest)
    }

    private func importSummary(_ snapshot: Snapshot, previous: Snapshot?, isNewest: Bool) -> AppAlert {
        var lines = ["\(snapshot.followers.count.formatted()) followers, \(snapshot.following.count.formatted()) following."]
        if let previous, isNewest {
            let lost = Analyzer.diff(from: previous, to: snapshot).lostFollowers.count
            lines.append("Since \(previous.takenAt.mediumDay), \(peopleCount(lost)) stopped following you.")
        } else if !isNewest {
            lines.append("It's older than your latest export, so it was added to the history.")
        } else {
            lines.append("Import another export in a week or two to see who unfollows you.")
        }
        if snapshot.fromHTML {
            lines.append("This export is HTML, which has no follow dates. Choose JSON next time for better results.")
        }
        return AppAlert(title: "Export of \(snapshot.takenAt.mediumDay)", message: lines.joined(separator: " "))
    }

    private func persist(_ snapshot: Snapshot) {
        guard !snapshot.isSample else { return }
        do {
            try storage.save(snapshot)
        } catch {
            alert = AppAlert(title: "Couldn't save the export", message: error.localizedDescription)
        }
    }

    // MARK: - Removing

    func delete(_ snapshot: Snapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        try? storage.delete(snapshot.id)
        refresh()
    }

    func deleteEverything() {
        try? storage.deleteAll()
        snapshots = []
        decisions = [:]
        selectedOwner = nil
    }

    // MARK: - Sample data

    func loadSample() {
        snapshots.removeAll(where: \.isSample)
        snapshots += SampleData.snapshots()
        selectedOwner = Self.sampleOwner
    }

    func removeSample() {
        guard snapshots.contains(where: \.isSample) else { return }
        snapshots.removeAll(where: \.isSample)
        decisions[Self.sampleOwner] = nil
        selectedOwner = nil
    }

    // MARK: - Instagram

    /// Opens a profile in the Instagram app, or on the web when the app isn't installed.
    func open(_ username: String, with openURL: OpenURLAction, askOnReturn: Bool) {
        guard !isShowingSample else {
            alert = AppAlert(title: "Sample account", message: "Sample usernames are made up, so they don't open in Instagram.")
            return
        }
        if askOnReturn { awaitingReturn = username }
        openURL(Instagram.profile(username)) { accepted in
            if !accepted { openURL(Instagram.web(username)) }
        }
    }

    #if DEBUG
    /// `-sample` loads the demo data and `-import <path>` imports a file at
    /// launch, so the simulator can be driven from the command line.
    private func handleLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-sample") {
            loadSample()
        }
        if let index = arguments.firstIndex(of: "-import"), index + 1 < arguments.count {
            importFiles([URL(fileURLWithPath: arguments[index + 1])])
        }
    }
    #endif
}

func peopleCount(_ count: Int) -> String {
    count == 1 ? "1 person" : "\(count.formatted()) people"
}
