import Foundation

/// The relationship files in an export's followers_and_following folder.
public enum ExportFileKind: String, CaseIterable, Sendable {
    case followers
    case following
    case closeFriends
    case hiddenStoryFrom
    case pendingRequests
    case sentRequests
    case receivedRequests
    case recentlyUnfollowed
    case likedPosts
    case comments
    case storyLikes
    case savedPosts
    case viewedPosts
    case viewedVideos

    /// The activity log a file holds, for the files that are activity logs.
    public var activityKind: ActivityKind? {
        switch self {
        case .likedPosts: .likedPost
        case .comments: .comment
        case .storyLikes: .storyLike
        case .savedPosts: .saved
        case .viewedPosts: .viewedPost
        case .viewedVideos: .viewedVideo
        default: nil
        }
    }

    /// Classifies a path inside an export by its file name. Returns nil for
    /// everything the app does not read.
    public static func classify(_ path: String) -> (kind: ExportFileKind, isHTML: Bool)? {
        let lowered = path.lowercased()
        guard !lowered.contains("__macosx") else { return nil }
        let file = lowered.split(separator: "/").last.map(String.init) ?? lowered
        let isHTML: Bool
        if file.hasSuffix(".json") {
            isHTML = false
        } else if file.hasSuffix(".html") {
            isHTML = true
        } else {
            return nil
        }
        let base = file.dropLast(5)

        let kind: ExportFileKind?
        switch base {
        case "following": kind = .following
        case "close_friends": kind = .closeFriends
        case "hide_story_from": kind = .hiddenStoryFrom
        case "pending_follow_requests": kind = .pendingRequests
        case "recent_follow_requests", "permanent_follow_requests": kind = .sentRequests
        case "recently_unfollowed_profiles", "recently_unfollowed_accounts", "recently_unfollowed", "unfollowed_profiles":
            kind = .recentlyUnfollowed
        case "liked_posts": kind = .likedPosts
        case "story_likes": kind = .storyLikes
        case "saved_posts": kind = .savedPosts
        case "posts_viewed": kind = .viewedPosts
        case "videos_watched": kind = .viewedVideos
        case _ where base.hasPrefix("post_comments") || base.hasPrefix("reels_comments"): kind = .comments
        default:
            if base == "followers" || (base.hasPrefix("followers_") && base.count > 10 && base.dropFirst(10).allSatisfy(\.isNumber)) {
                kind = .followers
            } else if base.hasPrefix("follow_requests_you") {
                kind = .receivedRequests
            } else {
                kind = nil
            }
        }
        return kind.map { ($0, isHTML) }
    }
}

/// Accounts read from one export file.
public struct ParsedFile: Sendable {
    public var accounts: [Account]
    /// Entries that looked like accounts, whether or not a username came out of them.
    public var recordCount: Int
}

/// Turns the JSON and HTML files of an Instagram export into accounts.
///
/// Instagram has shipped at least three record shapes for the same lists:
///
/// - Before 2024: `string_list_data[0].value` holds the username.
/// - 2024 to mid 2026: `title` holds it and `value` is gone.
/// - From August 2026: `label_values` pairs, where the username's label is
///   translated into the account's language ("Username", "Nome de usuário").
///
/// The parser accepts all three. For the labelled shape it finds the username
/// label by what the values look like, so it does not need a translation table.
public enum ExportParser {
    public static func parseJSON(_ data: Data) throws -> ParsedFile {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ExportReadError.notJSON
        }
        var records: [[String: Any]] = []
        collectRecords(in: object, into: &records)
        let labels = resolveLabels(records)

        var seen = Set<String>()
        var accounts: [Account] = []
        for record in records {
            guard let account = account(from: record, labels: labels), seen.insert(account.username).inserted else { continue }
            accounts.append(account)
        }
        return ParsedFile(accounts: accounts, recordCount: records.count)
    }

    /// Reads usernames from the HTML version of an export. HTML files carry
    /// dates only as localized text, so these accounts have no `since`.
    public static func parseHTML(_ data: Data) -> ParsedFile {
        let html = String(decoding: data, as: UTF8.self)
        var seen = Set<String>()
        var accounts: [Account] = []
        var links = 0
        var searchStart = html.startIndex
        while let match = html.range(of: "instagram.com/", range: searchStart..<html.endIndex) {
            var end = match.upperBound
            while end < html.endIndex, !"\"' <>".contains(html[end]) {
                end = html.index(after: end)
            }
            links += 1
            if let username = usernameFromURL("https://www." + html[match.lowerBound..<end]), seen.insert(username).inserted {
                accounts.append(Account(username: username))
            }
            searchStart = end
        }
        return ParsedFile(accounts: accounts, recordCount: links)
    }

    // MARK: - Activity

    /// One entry of an activity log: whose content it was and when.
    public struct ActivityEntry: Hashable, Sendable {
        public var username: String
        public var date: Date
    }

    /// Owner keys of the older formats, and the English label of the 2026 one.
    private static let knownOwnerKeys: Set<String> = ["author", "media owner", "owner", "username"]

    /// Reads an activity log (likes, comments, story likes, saves, viewed posts
    /// or videos) into the owner of each piece of content and the time.
    ///
    /// Older exports name the owner in `title` or under a key such as
    /// "Author" or "Media Owner". The 2026 format nests it two levels down,
    /// in an "Owner" group of label/value pairs with translated labels. Every
    /// string in a record is collected with its key, and the owner key is
    /// picked per file by the same value-shape inference used for the
    /// follower lists.
    public static func parseActivity(_ data: Data) throws -> (entries: [ActivityEntry], recordCount: Int) {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ExportReadError.notJSON
        }
        var records: [[String: Any]] = []
        collectActivityRecords(in: object, into: &records)
        let candidates = records.map(candidatePairs)

        var tallies: [String: Tally] = [:]
        for pairs in candidates {
            for (key, value) in pairs where !key.hasPrefix("#href") {
                tally(value, into: &tallies[key, default: Tally()])
            }
        }
        // Older logs keep the owner in `title`; the value beside it is usually
        // an emoji but can be any short word, so `title` is taken first.
        let titleKey = tallies["#title"].flatMap { Double($0.usernameLike) >= 0.9 * Double($0.filled) ? "#title" : nil }
        let ownerKey = tallies.keys.sorted().first {
            let label = repairMojibake($0).lowercased()
            return knownOwnerKeys.contains(label) || knownUsernameLabels.contains(label)
        } ?? titleKey ?? inferUsernameLabel(tallies)

        var entries: [ActivityEntry] = []
        for (record, pairs) in zip(records, candidates) {
            guard let date = latestTimestamp(in: record) else { continue }
            let owner = ownerKey.flatMap { key in pairs.first { $0.key == key }.flatMap { usernameValue($0.value) } }
                ?? pairs.lazy.compactMap { usernameFromURL($0.value) }.first
            if let owner {
                entries.append(ActivityEntry(username: owner, date: date))
            }
        }
        return (entries, records.count)
    }

    private static func collectActivityRecords(in object: Any, into records: inout [[String: Any]]) {
        if let dictionary = object as? [String: Any] {
            if dictionary["string_list_data"] is [Any] || dictionary["string_map_data"] is [String: Any] || dictionary["label_values"] is [Any] {
                records.append(dictionary)
                return
            }
            for key in dictionary.keys.sorted() {
                collectActivityRecords(in: dictionary[key]!, into: &records)
            }
        } else if let array = object as? [Any] {
            for element in array {
                collectActivityRecords(in: element, into: &records)
            }
        }
    }

    /// Every string in a record with the key it sits under. Links are kept
    /// under "#href" keys, as a fallback source of profile usernames only.
    private static func candidatePairs(_ record: [String: Any]) -> [(key: String, value: String)] {
        var pairs: [(key: String, value: String)] = []
        if let title = record["title"] as? String, !title.isEmpty {
            pairs.append(("#title", title))
        }
        for item in record["string_list_data"] as? [[String: Any]] ?? [] {
            if let value = item["value"] as? String { pairs.append(("#value", value)) }
            if let href = item["href"] as? String { pairs.append(("#href", href)) }
        }
        for (key, item) in (record["string_map_data"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let item = item as? [String: Any] else { continue }
            if let value = item["value"] as? String { pairs.append((key, value)) }
            if let href = item["href"] as? String { pairs.append(("#href", href)) }
        }
        flattenLabels(record["label_values"] as? [[String: Any]] ?? [], into: &pairs)
        return pairs
    }

    private static func flattenLabels(_ entries: [[String: Any]], into pairs: inout [(key: String, value: String)]) {
        for entry in entries {
            if let label = entry["label"] as? String, let value = entry["value"] as? String {
                pairs.append((label, value))
            }
            if let href = entry["href"] as? String {
                pairs.append(("#href", href))
            }
            if let nested = entry["dict"] as? [[String: Any]] {
                flattenLabels(nested, into: &pairs)
            }
        }
    }

    private static func latestTimestamp(in record: [String: Any]) -> Date? {
        var dates = [date(from: record["timestamp"])]
        for item in record["string_list_data"] as? [[String: Any]] ?? [] {
            dates.append(date(from: item["timestamp"]))
        }
        for item in (record["string_map_data"] as? [String: Any] ?? [:]).values {
            dates.append(date(from: (item as? [String: Any])?["timestamp"]))
        }
        return dates.compactMap { $0 }.max()
    }

    // MARK: - Records

    private static func collectRecords(in object: Any, into records: inout [[String: Any]]) {
        if let dictionary = object as? [String: Any] {
            if dictionary["string_list_data"] is [Any] || dictionary["label_values"] is [Any] {
                records.append(dictionary)
                return
            }
            for key in dictionary.keys.sorted() {
                collectRecords(in: dictionary[key]!, into: &records)
            }
        } else if let array = object as? [Any] {
            for element in array {
                collectRecords(in: element, into: &records)
            }
        }
    }

    private static func account(from record: [String: Any], labels: Labels) -> Account? {
        var username: String?
        var name: String?
        var since = date(from: record["timestamp"])

        if let list = record["string_list_data"] as? [[String: Any]], let first = list.first {
            username = usernameValue(first["value"]) ?? usernameValue(record["title"]) ?? usernameFromURL(first["href"])
            since = date(from: first["timestamp"]) ?? since
        }

        if username == nil, let pairs = record["label_values"] as? [[String: Any]] {
            if let label = labels.username {
                username = pairs.first { $0["label"] as? String == label }.flatMap { usernameValue($0["value"]) }
            }
            if username == nil {
                username = pairs.lazy.compactMap { usernameFromURL($0["href"]) ?? usernameFromURL($0["value"]) }.first
            }
            if let label = labels.name, let raw = pairs.first(where: { $0["label"] as? String == label })?["value"] as? String {
                name = displayName(raw)
            }
        }

        if username == nil {
            username = usernameValue(record["title"])
        }
        guard let username else { return nil }

        let fbid = (record["fbid"] as? String) ?? (record["fbid"] as? NSNumber)?.stringValue
        return Account(username: username, name: name, since: since, fbid: fbid)
    }

    // MARK: - Labels

    struct Labels {
        var username: String?
        var name: String?
    }

    private struct Tally {
        var filled = 0
        var usernameLike = 0
        var nameLike = 0
    }

    /// Labels known to mean "username", compared after repairing the export's
    /// double-encoded UTF-8. Inference covers every other language.
    private static let knownUsernameLabels: Set<String> = [
        "username", "nome de usuário", "nombre de usuario", "nom d'utilisateur", "nom d\u{2019}utilisateur",
        "benutzername", "nome utente", "gebruikersnaam", "имя пользователя", "kullanıcı adı", "nazwa użytkownika",
    ]

    static func resolveLabels(_ records: [[String: Any]]) -> Labels {
        var tallies: [String: Tally] = [:]
        for record in records {
            guard let pairs = record["label_values"] as? [[String: Any]] else { continue }
            for pair in pairs {
                guard let label = pair["label"] as? String else { continue }
                tally(pair["value"] as? String, into: &tallies[label, default: Tally()])
            }
        }
        guard !tallies.isEmpty else { return Labels() }

        let username = tallies.keys.sorted().first { knownUsernameLabels.contains(repairMojibake($0).lowercased()) }
            ?? inferUsernameLabel(tallies)
        let name = tallies
            .filter { $0.key != username && $0.value.filled > 0 && Double($0.value.nameLike) >= 0.3 * Double($0.value.filled) }
            .max { ($0.value.nameLike, $1.key) < ($1.value.nameLike, $0.key) }?
            .key
        return Labels(username: username, name: name)
    }

    private static func tally(_ raw: String?, into tally: inout Tally) {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        tally.filled += 1
        if value.contains("://") {
            // URLs are neither usernames nor display names.
        } else if usernameValue(value) != nil {
            tally.usernameLike += 1
        } else if value.contains(where: \.isLetter), value.filter(\.isNumber).count * 10 < value.count * 3 {
            // Letters and few digits: a display name rather than a date or a count.
            tally.nameLike += 1
        }
    }

    /// Picks the label whose values are almost all valid usernames. Display
    /// names are sometimes username-shaped ("ana"), so the winner must clearly
    /// beat the runner-up or no label is chosen.
    private static func inferUsernameLabel(_ tallies: [String: Tally]) -> String? {
        let mostFilled = tallies.values.map(\.filled).max() ?? 0
        guard mostFilled > 0 else { return nil }
        let ranked = tallies
            .filter { $0.value.filled * 2 >= mostFilled }
            .map { (label: $0.key, rate: Double($0.value.usernameLike) / Double($0.value.filled)) }
            .sorted { ($0.rate, $1.label) > ($1.rate, $0.label) }
        guard let winner = ranked.first, winner.rate >= 0.75 else { return nil }
        if ranked.count > 1, winner.rate < ranked[1].rate * 1.5 { return nil }
        return winner.label
    }

    // MARK: - Values

    /// Instagram usernames: lowercase letters, digits, periods and underscores, at most 30 characters.
    public static func isValidUsername(_ value: String) -> Bool {
        guard (1...30).contains(value.utf8.count) else { return false }
        return value.utf8.allSatisfy { byte in
            (0x61...0x7A).contains(byte) || (0x30...0x39).contains(byte) || byte == 0x2E || byte == 0x5F
        }
    }

    static func usernameValue(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        if raw.contains("instagram.com/") { return usernameFromURL(raw) }
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if candidate.hasPrefix("@") { candidate.removeFirst() }
        return isValidUsername(candidate) ? candidate : nil
    }

    private static let nonProfilePaths: Set<String> = ["p", "reel", "reels", "stories", "explore", "accounts", "direct", "tv"]

    static func usernameFromURL(_ value: Any?) -> String? {
        guard let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.contains("instagram.com/"),
              let url = URL(string: raw) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && $0 != "_u" }
        guard parts.count == 1 else { return nil }
        let candidate = parts[0].lowercased()
        return isValidUsername(candidate) && !nonProfilePaths.contains(candidate) ? candidate : nil
    }

    private static func date(from value: Any?) -> Date? {
        let seconds: Double
        if let number = value as? NSNumber {
            seconds = number.doubleValue
        } else if let string = value as? String, let parsed = Double(string) {
            seconds = parsed
        } else {
            return nil
        }
        guard seconds > 0 else { return nil }
        // Some Meta exports use milliseconds.
        return Date(timeIntervalSince1970: seconds > 100_000_000_000 ? seconds / 1000 : seconds)
    }

    private static func displayName(_ raw: String) -> String? {
        let cleaned = repairMojibake(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Meta writes non-ASCII text as UTF-8 bytes escaped one by one (`Ã©`
    /// for "é"), so JSON decoding yields Latin-1 mojibake. Re-reading those code
    /// points as bytes recovers the text; anything else is returned unchanged.
    public static func repairMojibake(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard scalars.contains(where: { $0.value >= 0x80 }), scalars.allSatisfy({ $0.value <= 0xFF }) else { return text }
        return String(bytes: scalars.map { UInt8($0.value) }, encoding: .utf8) ?? text
    }
}
