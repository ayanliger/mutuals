import Foundation
import Testing
@testable import MutualsCore

struct ZipReaderTests {
    @Test func readsDeflatedAndStoredEntries() throws {
        let scratch = try Scratch()
        let long = String(repeating: "followers and following ", count: 2_000)
        try scratch.write(long, to: "src/a/long.txt")
        try scratch.write("short", to: "src/b/short.txt")
        try scratch.write("", to: "src/empty.txt")

        for arguments in [[], ["-0"]] {
            let archive = try scratch.zip("src", to: "out\(arguments.count).zip", arguments: arguments)
            let reader = try ZipReader(url: archive)
            let files = Dictionary(uniqueKeysWithValues: reader.entries.filter { !$0.isDirectory }.map { ($0.path, $0) })

            #expect(Set(files.keys) == ["a/long.txt", "b/short.txt", "empty.txt"])
            #expect(try reader.data(for: #require(files["a/long.txt"])) == Data(long.utf8))
            #expect(try reader.data(for: #require(files["b/short.txt"])) == Data("short".utf8))
            #expect(try reader.data(for: #require(files["empty.txt"])).isEmpty)
            if arguments.isEmpty {
                #expect(try #require(files["a/long.txt"]).method == 8)
            }
        }
    }

    @Test func readsZip64Archives() throws {
        // Info-ZIP writes ZIP64 records when it streams from standard input.
        let scratch = try Scratch()
        let payload = Data(String(repeating: "zip64 ", count: 5_000).utf8)
        let archive = scratch.url.appendingPathComponent("stream.zip")
        try scratch.run("/usr/bin/zip", ["-q", archive.path, "-"], input: payload)

        let reader = try ZipReader(url: archive)
        let entry = try #require(reader.entries.first)
        #expect(reader.entries.count == 1)
        #expect(try reader.data(for: entry) == payload)
    }

    @Test func rejectsFilesThatAreNotZips() throws {
        let scratch = try Scratch()
        let file = try scratch.write("{\"not\": \"a zip\"}", to: "plain.json")
        #expect(throws: ZipReader.Failure.notAZip) { try ZipReader(url: file) }
    }

    @Test func detectsCorruptedData() throws {
        let scratch = try Scratch()
        try scratch.write(String(repeating: "abc", count: 100), to: "src/file.txt")
        let archive = try scratch.zip("src", to: "out.zip", arguments: ["-0"])

        // Flip one byte of the stored payload; the CRC must catch it.
        var bytes = try Data(contentsOf: archive)
        let reader = try ZipReader(url: archive)
        let entry = try #require(reader.entries.first { $0.path == "file.txt" })
        let payloadStart = Int(entry.localHeaderOffset) + 30 + "file.txt".utf8.count
        let headerExtra = Int(bytes[Int(entry.localHeaderOffset) + 28]) | Int(bytes[Int(entry.localHeaderOffset) + 29]) << 8
        bytes[payloadStart + headerExtra] ^= 0xFF
        try bytes.write(to: archive)

        let damaged = try ZipReader(url: archive)
        #expect(throws: ZipReader.Failure.self) { try damaged.data(for: entry) }
    }
}
