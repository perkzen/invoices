import Foundation
import Testing
@testable import Invoices

@Suite("Command line tool")
struct CommandLineToolTests {
    private func directory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "invoices-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func destination(of link: URL) throws -> String {
        try FileManager.default.destinationOfSymbolicLink(atPath: link.path(percentEncoded: false))
    }

    @Test func `the installed link points at the tool inside the app`() throws {
        let bin = try directory()
        defer { try? FileManager.default.removeItem(at: bin) }
        let helper = URL(fileURLWithPath: "/Applications/Invoices.app/Contents/Helpers/invoices")

        let link = try CommandLineTool.install(helper, in: bin)

        #expect(link == bin.appending(path: "invoices"))
        #expect(try destination(of: link) == helper.path(percentEncoded: false))
    }

    /// The link outlives the app it was made from — a copy deleted and
    /// installed again leaves it dangling, and installing over it is the fix.
    @Test func `installing again replaces a link left dangling`() throws {
        let bin = try directory()
        defer { try? FileManager.default.removeItem(at: bin) }
        let gone = URL(fileURLWithPath: "/Volumes/nowhere/Invoices.app/Contents/Helpers/invoices")
        let helper = URL(fileURLWithPath: "/Applications/Invoices.app/Contents/Helpers/invoices")
        try CommandLineTool.install(gone, in: bin)

        let link = try CommandLineTool.install(helper, in: bin)

        #expect(try destination(of: link) == helper.path(percentEncoded: false))
    }

    /// Someone else's `invoices` is not ours to replace, however it got there.
    @Test func `a file that is not a link is refused, and left as it was`() throws {
        let bin = try directory()
        defer { try? FileManager.default.removeItem(at: bin) }
        let theirs = bin.appending(path: "invoices")
        let script = Data("#!/bin/sh\necho theirs\n".utf8)
        try script.write(to: theirs)

        #expect(throws: CommandLineTool.InstallError.self) {
            try CommandLineTool.install(
                URL(fileURLWithPath: "/Applications/Invoices.app/Contents/Helpers/invoices"), in: bin
            )
        }
        #expect(try Data(contentsOf: theirs) == script)
    }
}
