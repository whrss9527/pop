import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pop

final class TidyFolderTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testKindsByExtension() {
        func kind(_ name: String) -> FolderTidy.Kind { FolderTidy.kind(of: URL(fileURLWithPath: "/tmp/\(name)")) }
        XCTAssertEqual(kind("截图.PNG"), .images)
        XCTAssertEqual(kind("海边.heic"), .images)
        XCTAssertEqual(kind("发布会.mp4"), .videos)
        XCTAssertEqual(kind("录像.mov"), .videos)
        XCTAssertEqual(kind("会议.m4a"), .audio)
        XCTAssertEqual(kind("歌.mp3"), .audio)
        XCTAssertEqual(kind("报告.pdf"), .documents)
        XCTAssertEqual(kind("合同.docx"), .documents)
        XCTAssertEqual(kind("预算.xlsx"), .documents)
        XCTAssertEqual(kind("笔记.md"), .documents)
        XCTAssertEqual(kind("资料.rar"), .archives)
        XCTAssertEqual(kind("代码.tar.gz"), .archives)
        XCTAssertEqual(kind("安装器.dmg"), .installers)
        XCTAssertEqual(kind("驱动.pkg"), .installers)
        XCTAssertEqual(kind("没有扩展名"), .others)
        XCTAssertEqual(FolderTidy.month(of: Date(timeIntervalSince1970: 1_790_000_000), calendar: utc), "2026-09")
    }

    func testPlanSkipsFoldersHiddenAndUnfinishedFiles() {
        let folder = URL(fileURLWithPath: "/tmp/pop-tidy-\(UUID().uuidString)", isDirectory: true)
        let items = TidyFolderPlugin.demoItems(in: folder) + [
            FolderTidy.Item(url: folder.appending(path: ".DS_Store"), isDirectory: false, added: nil),
            FolderTidy.Item(url: folder.appending(path: "Firefox.part"), isDirectory: false, added: Date()),
        ]
        let plan = FolderTidy.plan(items, in: folder, mode: .kind, calendar: utc)
        XCTAssertEqual(plan.moves.count, 14)
        XCTAssertEqual(plan.groups.map(\.name), ["图像", "视频", "音频", "文档", "压缩包", "安装包", "其他"])
        XCTAssertEqual(plan.groups.map(\.count), [3, 1, 2, 4, 2, 1, 1])
        let movedNames = Set(plan.moves.map(\.from.lastPathComponent))
        XCTAssertFalse(movedNames.contains("项目"))
        XCTAssertFalse(movedNames.contains("大文件.zip.crdownload"))
        XCTAssertFalse(movedNames.contains(".DS_Store"))
        XCTAssertEqual(plan.moves.first { $0.from.lastPathComponent == "季度报告.pdf" }?.to.path(percentEncoded: false),
                       folder.appending(path: "文档/季度报告.pdf").path(percentEncoded: false))

        let months = FolderTidy.plan(items, in: folder, mode: .month, calendar: utc)
        XCTAssertEqual(months.groups.map(\.name), ["2026-09", "2026-08", "2026-07"])
        XCTAssertEqual(months.groups.map(\.count), [4, 5, 5])
    }

    func testApplyAndUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-tidy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // 「文档」子文件夹已经有了，里面还有一个同名的文件
        try FileManager.default.createDirectory(at: folder.appending(path: "文档"), withIntermediateDirectories: true)
        for name in ["a.png", "b.pdf", "c.zip", "文档/b.pdf"] {
            try Data(name.utf8).write(to: folder.appending(path: name))
        }
        let plan = FolderTidy.plan(try FolderTidy.items(in: folder), in: folder, mode: .kind)
        XCTAssertEqual(plan.groups.map(\.name), ["图像", "文档", "压缩包"])
        let done = try FolderTidy.apply(plan)
        XCTAssertEqual(done.moves.count, 3)
        XCTAssertEqual(Set(done.createdFolders.map(\.lastPathComponent)), ["图像", "压缩包"])
        let manager = FileManager.default
        XCTAssertTrue(manager.fileExists(atPath: folder.appending(path: "图像/a.png").path(percentEncoded: false)))
        // 重名的加 2，原来那个不动
        XCTAssertTrue(manager.fileExists(atPath: folder.appending(path: "文档/b 2.pdf").path(percentEncoded: false)))
        XCTAssertEqual(try String(contentsOf: folder.appending(path: "文档/b.pdf"), encoding: .utf8), "文档/b.pdf")

        try FolderTidy.undo(done)
        for name in ["a.png", "b.pdf", "c.zip"] {
            XCTAssertTrue(manager.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false)), name)
        }
        // 新建的子文件夹删掉了，原来就有的留着
        XCTAssertFalse(manager.fileExists(atPath: folder.appending(path: "图像").path(percentEncoded: false)))
        XCTAssertFalse(manager.fileExists(atPath: folder.appending(path: "压缩包").path(percentEncoded: false)))
        XCTAssertTrue(manager.fileExists(atPath: folder.appending(path: "文档/b.pdf").path(percentEncoded: false)))
    }

    func testSortsPhotosByCaptureDate() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-tidy-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // 一张 EXIF 里写着拍摄时间的照片和一个文档
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let photo = folder.appending(path: "IMG_0001.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(photo as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let exif: [CFString: Any] = [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2025:07:14 10:20:30"]]
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), exif as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try Data("说明".utf8).write(to: folder.appending(path: "说明.txt"))

        let items = try FolderTidy.items(in: folder)
        XCTAssertEqual(items.first { $0.url.lastPathComponent == "IMG_0001.jpg" }?.taken, FolderTidy.exifDate("2025:07:14 10:20:30"))
        XCTAssertNil(items.first { $0.url.lastPathComponent == "说明.txt" }?.taken)
        XCTAssertNil(FolderTidy.exifDate("不是时间"))
        let plan = FolderTidy.plan(items, in: folder, mode: .taken)
        XCTAssertEqual(plan.groups.map(\.name), ["2025-07"])
        XCTAssertEqual(plan.groups.first?.symbol, "camera")
        XCTAssertEqual(plan.moves.map { $0.to.path(percentEncoded: false) }, [folder.appending(path: "2025-07/IMG_0001.jpg").path(percentEncoded: false)])
        XCTAssertEqual(FolderTidy.Mode.allCases.map(\.title), ["按类型", "按月份", "按拍摄日期"])
    }

    @MainActor
    func testCaptureDateSummary() {
        let folder = URL(fileURLWithPath: "/tmp/pop-tidy-\(UUID().uuidString)", isDirectory: true)
        var photo = FolderTidy.Item(url: folder.appending(path: "a.jpg"), isDirectory: false, added: Date())
        photo.taken = Date(timeIntervalSince1970: 1_790_000_000)
        let model = TidyFolderModel(folder: folder, items: [photo, FolderTidy.Item(url: folder.appending(path: "b.pdf"), isDirectory: false, added: Date())],
                                    mode: .taken)
        XCTAssertEqual(model.summary, "会把 1 张照片和视频按拍摄的月份放进 1 个子文件夹；别的文件不动")
        XCTAssertEqual(TidyFolderModel(folder: folder, items: [], mode: .taken).summary, "没有读得到拍摄日期的照片和视频")
    }

    func testAvailableNames() {
        XCTAssertEqual(FolderTidy.available("a.png", used: []), "a.png")
        XCTAssertEqual(FolderTidy.available("a.png", used: ["a.png"]), "a 2.png")
        XCTAssertEqual(FolderTidy.available("A.png", used: ["a.png", "a 2.png"]), "A 3.png")
        XCTAssertEqual(FolderTidy.available("说明", used: ["说明"]), "说明 2")
    }

    @MainActor
    func testWhichFolderAndCard() throws {
        let downloads = TidyFolderPlugin.folder(for: [])
        XCTAssertEqual(downloads.lastPathComponent, "Downloads")
        let temp = FileManager.default.temporaryDirectory
        func path(_ url: URL) -> String {
            url.standardizedFileURL.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        XCTAssertEqual(path(TidyFolderPlugin.folder(for: [temp])), path(temp))
        XCTAssertEqual(path(TidyFolderPlugin.folder(for: [temp.appending(path: "不存在.txt")])), path(temp))

        let folder = temp.appending(path: "pop-demo-\(UUID().uuidString)", directoryHint: .isDirectory)
        let model = TidyFolderModel(folder: folder, items: TidyFolderPlugin.demoItems(in: folder), mode: .kind)
        XCTAssertEqual(model.summary, "会把 14 个文件放进 7 个子文件夹；子文件夹、隐藏文件和没下载完的文件不动")
        XCTAssertEqual(TidyFolderModel(folder: folder, items: [], mode: .month).summary, "没有要整理的文件")
        XCTAssertTrue(TidyFolderPlugin().info.canHandle(.empty))
    }
}
