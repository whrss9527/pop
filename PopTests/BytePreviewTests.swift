import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import Pop

final class BytePreviewTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PopBytePreviewTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func file(_ data: Data, in folder: URL, name: String = "sample.bin") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func failure(_ expected: BytePreview.Failure, files: [URL], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try BytePreview.read(files), file: file, line: line) { error in
            XCTAssertEqual(error as? BytePreview.Failure, expected, file: file, line: line)
        }
    }

    func testReadOrdinaryFilePreservesSourceAndObservedSize() throws {
        let data = Data([0x00, 0x41, 0x1F, 0x7E, 0x7F, 0xFF])
        let url = try file(data, in: temporaryDirectory(), name: "字节 预览.bin")
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let preview = try BytePreview.read([url])
        XCTAssertEqual(preview.name, "字节 预览.bin")
        XCTAssertEqual(preview.data, data)
        XCTAssertEqual(preview.observedFileSize, 6)
        XCTAssertFalse(preview.truncated)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified)
    }

    func testEmptyFileHasNoInventedBytesOrRows() throws {
        let url = try file(Data(), in: temporaryDirectory())
        let preview = try BytePreview.read([url])
        XCTAssertEqual(preview.data, Data())
        XCTAssertEqual(preview.observedFileSize, 0)
        XCTAssertEqual(preview.text, "")
        XCTAssertFalse(preview.truncated)
    }

    func testFormattingShowsOffsetsHexAndOnlyPrintableASCII() {
        let text = BytePreview.format(Data([0x00, 0x41, 0x1F, 0x7E, 0x7F, 0xFF]))
        XCTAssertEqual(text, "00000000  00 41 1F 7E 7F FF                                |.A.~..          |")
        XCTAssertFalse(text.contains("\0"))
        XCTAssertFalse(text.contains("\u{1F}"))
    }

    func testRowsUseSixteenBytesAndLastLineIsPadded() {
        let lines = BytePreview.format(Data(0..<17)).split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], "00000000  00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F  |................|")
        XCTAssertEqual(lines[1], "00000010  10                                               |.               |")
        XCTAssertEqual(lines[0].count, lines[1].count)
    }

    func testPrintableRangeIncludesSpaceAndTildeButNotDELOrUTF8Bytes() {
        let text = BytePreview.format(Data([0x20, 0x21, 0x5C, 0x7E, 0x7F, 0xC3, 0xA9]))
        XCTAssertTrue(text.hasSuffix("| !\\~...         |"))
        XCTAssertFalse(text.contains("é"))
    }

    func testFileLimitIsExplicitAtBoundaryAndFormattingIsBounded() throws {
        let root = try temporaryDirectory()
        for size in [4095, 4096, 4097, 20_000] {
            let original = Data((0..<size).map { UInt8(truncatingIfNeeded: $0) })
            let url = try file(original, in: root)
            let preview = try BytePreview.read([url])
            XCTAssertEqual(preview.data, original.prefix(4096), "size=\(size)")
            XCTAssertEqual(preview.observedFileSize, Int64(size))
            XCTAssertEqual(preview.truncated, size > 4096)
            XCTAssertEqual(preview.text.split(separator: "\n").count, 256)
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
        let text = BytePreview.format(Data(repeating: 0x41, count: 20_000))
        XCTAssertEqual(text.split(separator: "\n").count, 256)
        XCTAssertTrue(text.split(separator: "\n").last?.hasPrefix("00000FF0") == true)
        XCTAssertEqual(text.utf8.count, 19_967)
    }

    func testSparseLargeFileOnlyReturnsBoundedPrefix() throws {
        let url = try file(Data([0x50, 0x4F, 0x50]), in: temporaryDirectory())
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 1 << 34)
        let preview = try BytePreview.read([url])
        XCTAssertEqual(preview.data.count, 4096)
        XCTAssertEqual(preview.data.prefix(3), Data([0x50, 0x4F, 0x50]))
        XCTAssertEqual(preview.observedFileSize, 1 << 34)
        XCTAssertTrue(preview.truncated)
    }

    func testZeroOrMultipleFilesAreRejectedRatherThanSilentlySelectingOne() throws {
        let url = try file(Data([1]), in: temporaryDirectory())
        failure(.requiresSingleFile, files: [])
        failure(.requiresSingleFile, files: [url, url])
    }

    func testNonLocalPathsAreRejected() throws {
        failure(.notLocalFile, files: [try XCTUnwrap(URL(string: "https://example.com/private.bin"))])
        failure(.notLocalFile, files: [try XCTUnwrap(URL(string: "file://remote.example.com/private.bin"))])
    }

    func testEncodedNULCannotReadAnExistingPathPrefix() throws {
        let original = Data([0x50, 0x4F, 0x50])
        let prefix = try file(original, in: temporaryDirectory(), name: "visible")
        let encoded = try XCTUnwrap(URL(string: prefix.absoluteString + "%00hidden"))
        let files = [encoded]
        XCTAssertEqual(files.count, 1)
        XCTAssertNotNil(files.first)
        XCTAssertTrue(try XCTUnwrap(URLComponents(url: encoded, resolvingAgainstBaseURL: false)).percentEncodedPath.contains("%00"))
        failure(.notLocalFile, files: files)
        XCTAssertEqual(try Data(contentsOf: prefix), original)
    }

    func testRawNULInitializerIsRejectedAtItsObservableBoundary() throws {
        let prefix = try file(Data([1, 2, 3]), in: temporaryDirectory(), name: "visible")
        // 某些 Darwin Foundation 版本产生不可用的 URL 元素，数组的可观察数量可能已不是 1。
        let files = [URL(fileURLWithPath: prefix.path + "\0hidden")]
        let expected: BytePreview.Failure = files.count == 1 ? .notLocalFile : .requiresSingleFile
        failure(expected, files: files)
        XCTAssertEqual(try Data(contentsOf: prefix), Data([1, 2, 3]))
    }

    func testLiteralPercentZeroZeroInFilenameIsNotDecodedTwice() throws {
        let original = Data([0x41, 0x42])
        let url = try file(original, in: temporaryDirectory(), name: "visible%00hidden")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertTrue(components.percentEncodedPath.contains("%2500"))
        XCTAssertEqual(try BytePreview.read([url]).data, original)
    }

    func testDirectoryAndSymbolicLinkAreRejected() throws {
        let root = try temporaryDirectory()
        failure(.notRegularFile, files: [root])
        let target = try file(Data([1, 2, 3]), in: root)
        let link = root.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        failure(.notRegularFile, files: [link])
        try FileManager.default.removeItem(at: target)
        failure(.notRegularFile, files: [link])
    }

    func testFIFOIsRejectedWithoutWaitingForWriter() throws {
        let url = try temporaryDirectory().appendingPathComponent("pipe")
        let created = url.withUnsafeFileSystemRepresentation { path in mkfifo(path!, 0o600) }
        XCTAssertEqual(created, 0)
        let started = Date()
        failure(.notRegularFile, files: [url])
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testCharacterDeviceIsRejected() {
        failure(.notRegularFile, files: [URL(fileURLWithPath: "/dev/null")])
    }

    func testUnreadableFileFailsWithoutChangingPermissions() throws {
        guard geteuid() != 0 else { throw XCTSkip("root 可以读取没有权限的文件") }
        let url = try file(Data([1, 2, 3]), in: temporaryDirectory())
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        failure(.cannotRead, files: [url])
        let permissions = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue, 0)
    }

    func testMissingFileFailsWithoutCreatingAnything() throws {
        let root = try temporaryDirectory()
        let missing = root.appendingPathComponent("does-not-exist.bin")
        failure(.cannotRead, files: [missing])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testSuccessfulAndRejectedOpensCloseTheirDescriptors() throws {
        let root = try temporaryDirectory()
        let regular = try file(Data([1, 2, 3]), in: root)
        let pipe = root.appendingPathComponent("pipe")
        XCTAssertEqual(pipe.withUnsafeFileSystemRepresentation { mkfifo($0!, 0o600) }, 0)
        let descriptorFolder = FileManager.default.fileExists(atPath: "/proc/self/fd") ? "/proc/self/fd" : "/dev/fd"
        func count() throws -> Int { try FileManager.default.contentsOfDirectory(atPath: descriptorFolder).count }
        _ = try BytePreview.read([regular])
        failure(.notRegularFile, files: [root])
        failure(.notRegularFile, files: [pipe])
        let before = try count()
        for _ in 0..<64 {
            _ = try BytePreview.read([regular])
            failure(.notRegularFile, files: [root])
            failure(.notRegularFile, files: [pipe])
        }
        XCTAssertEqual(try count(), before)
    }
}
