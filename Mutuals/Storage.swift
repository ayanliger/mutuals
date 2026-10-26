import Foundation
import MutualsCore

/// Keeps snapshots and decisions as JSON files in Application Support, one
/// file per snapshot so deleting an export deletes one file.
nonisolated struct Storage: Sendable {
    private var root: URL {
        URL.applicationSupportDirectory.appending(path: "Mutuals", directoryHint: .isDirectory)
    }

    private var snapshotFolder: URL {
        root.appending(path: "Snapshots", directoryHint: .isDirectory)
    }

    private var decisionsFile: URL {
        root.appending(path: "decisions.json")
    }

    func loadSnapshots() -> [Snapshot] {
        let decoder = JSONDecoder()
        let files = (try? FileManager.default.contentsOfDirectory(at: snapshotFolder, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Snapshot.self, from: Data(contentsOf: $0)) }
            .sorted(by: Snapshot.chronological)
    }

    func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: snapshotFolder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotFolder.appending(path: "\(snapshot.id.uuidString).json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: snapshotFolder.appending(path: "\(id.uuidString).json"))
    }

    func loadDecisions() -> [String: [String: Decision]] {
        guard let data = try? Data(contentsOf: decisionsFile) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: Decision]].self, from: data)) ?? [:]
    }

    func save(decisions: [String: [String: Decision]]) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(decisions)
        try data.write(to: decisionsFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func deleteAll() throws {
        if FileManager.default.fileExists(atPath: root.path) {
            try FileManager.default.removeItem(at: root)
        }
    }
}
