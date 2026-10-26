import Foundation

public enum ExportReadError: LocalizedError, Equatable, Sendable {
    case noRelationshipFiles
    case missingFollowing
    case missingFollowers
    case notJSON
    case unreadableUsernames(file: String)
    case damaged(String)

    public var errorDescription: String? {
        switch self {
        case .noRelationshipFiles:
            "This doesn't look like an Instagram export."
        case .missingFollowing:
            "The export has no list of accounts you follow."
        case .missingFollowers:
            "The export has no list of your followers."
        case .notJSON:
            "A file in the export isn't valid JSON."
        case .unreadableUsernames(let file):
            "Couldn't find usernames in \(file)."
        case .damaged(let detail):
            "The archive is damaged (\(detail))."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noRelationshipFiles, .missingFollowing, .missingFollowers:
            "Request a new export with \"Followers and following\" selected, or pick the whole zip instead of a single file."
        case .unreadableUsernames:
            "Instagram may have changed its export format. Please open an issue with the file's structure (not your data)."
        case .notJSON, .damaged:
            "Download the export again and import the new copy."
        }
    }
}

/// Reads an Instagram export from a zip, an unzipped folder, or loose JSON/HTML files.
public enum ExportReader {
    private struct Candidate {
        let path: String
        let kind: ExportFileKind
        let isHTML: Bool
        let load: () throws -> Data
    }

    /// Builds a snapshot from the given files. Several URLs are merged, which
    /// covers exports Instagram splits into parts and people picking
    /// followers_1.json and following.json by hand.
    public static func read(_ urls: [URL], importedAt: Date = Date()) throws -> Snapshot {
        var candidates: [Candidate] = []
        var archiveDates: [Date] = []
        var owner: String?
        var nameDate: Date?

        for url in urls {
            if let parsed = exportName(url.lastPathComponent) {
                owner = owner ?? parsed.owner
                nameDate = nameDate ?? parsed.date
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let root = url.standardizedFileURL.path
                let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                while let file = files?.nextObject() as? URL {
                    let relative = String(file.standardizedFileURL.path.dropFirst(root.count))
                    guard let match = ExportFileKind.classify(relative) else { continue }
                    candidates.append(Candidate(path: relative, kind: match.kind, isHTML: match.isHTML) { try Data(contentsOf: file) })
                }
            } else if url.pathExtension.lowercased() == "zip" {
                let archive: ZipReader
                do {
                    archive = try ZipReader(url: url)
                } catch ZipReader.Failure.notAZip {
                    throw ExportReadError.damaged("not a zip file")
                } catch {
                    throw ExportReadError.damaged(String(describing: error))
                }
                for entry in archive.entries where !entry.isDirectory {
                    guard let match = ExportFileKind.classify(entry.path) else { continue }
                    if let modified = entry.modified { archiveDates.append(modified) }
                    candidates.append(Candidate(path: entry.path, kind: match.kind, isHTML: match.isHTML) { try archive.data(for: entry) })
                }
            } else if let match = ExportFileKind.classify(url.lastPathComponent) {
                candidates.append(Candidate(path: url.lastPathComponent, kind: match.kind, isHTML: match.isHTML) { try Data(contentsOf: url) })
            }
        }

        let byKind = chooseFiles(candidates)
        guard !byKind.isEmpty else { throw ExportReadError.noRelationshipFiles }
        guard byKind[.following] != nil else { throw ExportReadError.missingFollowing }
        guard byKind[.followers] != nil else { throw ExportReadError.missingFollowers }

        let following = try accounts(in: byKind[.following] ?? [], required: true)
        let followers = try accounts(in: byKind[.followers] ?? [], required: true)
        func optional(_ kind: ExportFileKind) -> [Account] {
            (try? accounts(in: byKind[kind] ?? [], required: false)) ?? []
        }

        let takenAt = exportDate(archiveDates: archiveDates, nameDate: nameDate, accounts: following + followers, importedAt: importedAt)
        return Snapshot(
            owner: owner,
            takenAt: takenAt,
            importedAt: importedAt,
            sourceName: urls.count == 1 ? urls[0].lastPathComponent : nil,
            followers: followers,
            following: following,
            closeFriends: Set(optional(.closeFriends).map(\.username)),
            hiddenStoryFrom: Set(optional(.hiddenStoryFrom).map(\.username)),
            pendingRequests: optional(.pendingRequests),
            sentRequests: Set(optional(.sentRequests).map(\.username)),
            receivedRequests: Set(optional(.receivedRequests).map(\.username)),
            recentlyUnfollowed: optional(.recentlyUnfollowed),
            fromHTML: (byKind[.following] ?? []).contains(where: \.isHTML)
        )
    }

    /// Picks which files to read for each kind. A file name can appear more
    /// than once in an archive; the copy under followers_and_following wins,
    /// and JSON wins over HTML.
    private static func chooseFiles(_ candidates: [Candidate]) -> [ExportFileKind: [Candidate]] {
        var chosen: [ExportFileKind: [Candidate]] = [:]
        for (kind, group) in Dictionary(grouping: candidates, by: \.kind) {
            var files = group
            let inFolder = files.filter { $0.path.lowercased().contains("followers_and_following") }
            if !inFolder.isEmpty { files = inFolder }
            let json = files.filter { !$0.isHTML }
            if !json.isEmpty { files = json }
            chosen[kind] = files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        return chosen
    }

    private static func accounts(in files: [Candidate], required: Bool) throws -> [Account] {
        var seen = Set<String>()
        var merged: [Account] = []
        for file in files {
            let data: Data
            do {
                data = try file.load()
            } catch {
                throw ExportReadError.damaged("\(file.path) couldn't be read")
            }
            let parsed = file.isHTML ? ExportParser.parseHTML(data) : try ExportParser.parseJSON(data)
            if required, parsed.recordCount > 0, parsed.accounts.isEmpty {
                throw ExportReadError.unreadableUsernames(file: file.path.split(separator: "/").last.map(String.init) ?? file.path)
            }
            for account in parsed.accounts where seen.insert(account.username).inserted {
                merged.append(account)
            }
        }
        return merged
    }

    /// Reads the account and date from Instagram's archive name,
    /// `instagram-<username>-<yyyy>-<mm>-<dd>-<id>.zip`. Usernames cannot
    /// contain hyphens, so splitting on them is unambiguous.
    public static func exportName(_ fileName: String) -> (owner: String, date: Date)? {
        let parts = fileName.split(separator: "-").map(String.init)
        guard parts.count >= 5, parts[0].lowercased() == "instagram",
              let year = Int(parts[2]), let month = Int(parts[3]), let day = Int(parts[4].prefix(2)),
              ExportParser.isValidUsername(parts[1].lowercased()) else { return nil }
        var components = DateComponents(year: year, month: month, day: day, hour: 12)
        components.timeZone = TimeZone(identifier: "UTC")
        guard let date = Calendar(identifier: .gregorian).date(from: components) else { return nil }
        return (parts[1].lowercased(), date)
    }

    /// Estimates when the export was generated. Entry timestamps inside the
    /// zip are the most precise source but carry no time zone, so they are
    /// trusted only when they agree with the date in the archive name.
    private static func exportDate(archiveDates: [Date], nameDate: Date?, accounts: [Account], importedAt: Date) -> Date {
        let plausible = archiveDates.filter { $0 > Date(timeIntervalSince1970: 1_420_070_400) }.max()
        var date: Date
        if let plausible, nameDate.map({ abs(plausible.timeIntervalSince($0)) < 3 * 86_400 }) ?? true {
            date = plausible
        } else {
            date = nameDate ?? importedAt
        }
        if let latest = accounts.compactMap(\.since).max(), latest > date {
            date = latest
        }
        return min(date, importedAt)
    }
}
