import Foundation
import Testing

/// A scratch directory removed when the value goes away.
final class Scratch {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("mutuals-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ text: String, to path: String) throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    /// Zips the contents of `folder` (relative to the scratch root) with Info-ZIP.
    func zip(_ folder: String, to name: String, arguments: [String] = []) throws -> URL {
        let archive = url.appendingPathComponent(name)
        try run("/usr/bin/zip", ["-q", "-r"] + arguments + [archive.path, "."], in: url.appendingPathComponent(folder))
        return archive
    }

    func run(_ tool: String, _ arguments: [String], in directory: URL? = nil, input: Data? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = directory ?? url
        let pipe = Pipe()
        if input != nil { process.standardInput = pipe }
        try process.run()
        if let input {
            pipe.fileHandleForWriting.write(input)
            try pipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(tool) \(arguments) failed")
    }
}

/// JSON for one entry of the pre-2024 shape, username in `value`.
func legacyEntry(_ username: String, _ timestamp: Int) -> String {
    #"{"title": "", "media_list_data": [], "string_list_data": [{"href": "https://www.instagram.com/\#(username)", "value": "\#(username)", "timestamp": \#(timestamp)}]}"#
}

/// JSON for one entry of the 2024-2026 shape, username in `title`.
func titledEntry(_ username: String, _ timestamp: Int) -> String {
    #"{"title": "\#(username)", "string_list_data": [{"href": "https://www.instagram.com/_u/\#(username)", "timestamp": \#(timestamp)}]}"#
}

/// JSON for one entry of the August 2026 shape, with labels as given.
func labelledEntry(usernameLabel: String, username: String, nameLabel: String, name: String, timestamp: Int) -> String {
    let object: [String: Any] = [
        "timestamp": timestamp,
        "media": [Any](),
        "label_values": [["label": usernameLabel, "value": username], ["label": nameLabel, "value": name]],
        "fbid": "100000\(timestamp)",
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

/// Meta's double-encoded UTF-8: each byte of the UTF-8 text becomes one code point.
func mojibake(_ text: String) -> String {
    String(String.UnicodeScalarView(text.utf8.map { Unicode.Scalar($0) }))
}

func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    var components = DateComponents(year: year, month: month, day: day, hour: hour)
    components.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: components)!
}
