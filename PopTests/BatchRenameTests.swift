import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pop

final class BatchRenameTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/pop-rename-plan", isDirectory: true)

    private func files(_ names: [String]) -> [URL] {
        names.map { folder.appending(path: $0) }
    }

    private func names(_ plan: BatchRename.Plan) -> [String] {
        plan.items.map(\.newName)
    }

    private func plan(_ names: [String], _ rule: BatchRename.Rule, dateNames: [String: String] = [:],
                      existing: Set<String> = []) -> BatchRename.Plan {
        let urls = BatchRename.ordered(files(names))
        let dates = Dictionary(uniqueKeysWithValues: dateNames.map { (folder.appending(path: $0.key), $0.value) })
        return BatchRename.plan(urls, rule: rule, dateNames: dates,
                                exists: { existing.contains($0.lastPathComponent) }, isFolder: { _ in false })
    }

    func testNumbersInNameOrder() {
        var rule = BatchRename.Rule()
        rule.name = "旅行"
        XCTAssertEqual(names(plan(["b.png", "a.png", "c 10.txt", "c 9.txt"], rule)),
                       ["旅行 01.png", "旅行 02.png", "旅行 03.txt", "旅行 04.txt"])
        rule.name = "旅行-"
        rule.start = 9
        rule.digits = 3
        XCTAssertEqual(names(plan(["a.png", "b.png"], rule)), ["旅行-009.png", "旅行-010.png"])
        rule.name = ""
        rule.digits = 1
        XCTAssertEqual(names(plan(["a.png", "b"], rule)), ["9.png", "10"])
    }

    func testReplaceAffixAndCase() {
        var rule = BatchRename.Rule(mode: .replace)
        rule.find = "IMG_"
        // 文件按名字排序，中文和英文谁在前面跟着系统语言，这里只比较有哪些名字
        XCTAssertEqual(Set(names(plan(["IMG_0001.JPG", "照片.jpg"], rule))), ["0001.JPG", "照片.jpg"])
        XCTAssertEqual(plan(["IMG_0001.JPG", "照片.jpg"], rule).changes.count, 1)

        rule.useRegex = true
        rule.find = #"(\d+)"#
        rule.replacement = "第$1张"
        XCTAssertEqual(names(plan(["IMG_0001.JPG"], rule)), ["IMG_第0001张.JPG"])
        rule.find = "("
        XCTAssertEqual(plan(["IMG_0001.JPG"], rule).error, "正则表达式有误")
        XCTAssertFalse(plan(["IMG_0001.JPG"], rule).canApply)

        var affix = BatchRename.Rule(mode: .affix)
        affix.prefix = "2026 "
        affix.suffix = " 定稿"
        XCTAssertEqual(Set(names(plan(["报告.pdf", "archive.tar.gz"], affix))), ["2026 archive.tar 定稿.gz", "2026 报告 定稿.pdf"])

        var letters = BatchRename.Rule(mode: .letterCase)
        letters.letterCase = .upper
        XCTAssertEqual(names(plan(["Report final.pdf"], letters)), ["REPORT FINAL.pdf"])
        letters.letterCase = .capitalized
        XCTAssertEqual(names(plan(["hello world.txt"], letters)), ["Hello World.txt"])
    }

    func testCaptureDatesKeepOrderAndNumberDuplicates() {
        let rule = BatchRename.Rule(mode: .captureDate)
        let result = plan(["IMG_1.jpg", "IMG_2.jpg", "notes.txt"], rule,
                          dateNames: ["IMG_1.jpg": "2026-09-27 17.42.18", "IMG_2.jpg": "2026-09-27 17.42.18"])
        XCTAssertEqual(names(result), ["2026-09-27 17.42.18.jpg", "2026-09-27 17.42.18 2.jpg", "notes.txt"])
    }

    func testProblems() {
        var rule = BatchRename.Rule(mode: .replace)
        rule.find = "a"
        rule.replacement = "b"
        // a.txt 改成 b.txt，和原来的 b.txt 撞名（b.txt 自己不变）
        let clash = plan(["a.txt", "b.txt"], rule, existing: ["a.txt", "b.txt"])
        XCTAssertEqual(clash.items.map(\.problem), ["和另一个文件重名", "和另一个文件重名"])
        XCTAssertFalse(clash.canApply)

        // 文件夹里已经有别的文件叫这个名字
        let taken = plan(["a.txt"], rule, existing: ["a.txt", "b.txt"])
        XCTAssertEqual(taken.items.first?.problem, "文件夹里已经有这个名字")

        // 改成的名字正好是另一个也要改名的文件原来的名字：不算冲突
        var shift = BatchRename.Rule()
        shift.start = 2
        shift.digits = 1
        let chain = plan(["1.txt", "2.txt"], shift, existing: ["1.txt", "2.txt"])
        XCTAssertEqual(names(chain), ["2.txt", "3.txt"])
        XCTAssertTrue(chain.canApply)

        rule.find = "a"
        rule.replacement = "a/b"
        XCTAssertEqual(plan(["a.txt"], rule).items.first?.problem, "名字里不能有 / 或 :")
        rule.replacement = ""
        XCTAssertEqual(plan(["a.txt"], rule).items.first?.problem, "名字不能是空的")
        rule.find = "note"
        rule.replacement = ".note"
        XCTAssertEqual(plan(["note.txt"], rule).items.first?.problem, "以 . 开头的文件会被隐藏")
    }

    func testApplySwapsAndUndoes() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let one = folder.appending(path: "one.txt")
        let two = folder.appending(path: "two.txt")
        try Data("1".utf8).write(to: one)
        try Data("2".utf8).write(to: two)
        func listing() throws -> [String] {
            try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
        }

        // 只改大小写
        var rule = BatchRename.Rule(mode: .letterCase)
        rule.letterCase = .upper
        let plan = BatchRename.plan(BatchRename.ordered([two, one]), rule: rule)
        XCTAssertTrue(plan.canApply, "\(plan)")
        let moves = try BatchRename.apply(plan)
        XCTAssertEqual(moves.count, 2)
        XCTAssertEqual(try listing(), ["ONE.txt", "TWO.txt"])
        try BatchRename.undo(moves)
        XCTAssertEqual(try listing(), ["one.txt", "two.txt"])

        // 两个文件互换名字
        try BatchRename.perform([BatchRename.Move(from: one, to: two), BatchRename.Move(from: two, to: one)])
        XCTAssertEqual(try String(contentsOf: one, encoding: .utf8), "2")
        XCTAssertEqual(try String(contentsOf: two, encoding: .utf8), "1")

        // 中途失败（要改成的名字已经被占了）就全部改回去
        let blocker = folder.appending(path: "blocked.txt")
        try Data("x".utf8).write(to: blocker)
        XCTAssertThrowsError(try BatchRename.perform([BatchRename.Move(from: one, to: folder.appending(path: "fine.txt")),
                                                      BatchRename.Move(from: two, to: blocker)]))
        XCTAssertEqual(try listing(), ["blocked.txt", "one.txt", "two.txt"])
    }

    func testDateNamesPreferTheCaptureTime() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-rename-dates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appending(path: "IMG_1.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(photo as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:09:27 17:42:18"] as [CFString: Any],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let note = folder.appending(path: "notes.txt")
        try Data("周一".utf8).write(to: note)

        let names = BatchRename.dateNames(for: [photo, note])
        XCTAssertEqual(names[photo], "2026-09-27 17.42.18")
        // 没有拍摄时间的按修改时间
        XCTAssertNotNil(names[note]?.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2}$"#, options: .regularExpression))
    }

    @MainActor
    func testPluginOpensTheRenameCard() async {
        let selected = files(["b.txt", "a.txt"])
        let outcome = await BatchRenamePlugin().run(ContentClassifier.classify(.files(selected)),
                                                    context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .present = outcome else { return XCTFail("应该弹出批量重命名卡片") }
        let model = RenameModel(files: selected)
        XCTAssertEqual(model.files.map(\.lastPathComponent), ["a.txt", "b.txt"])
        model.rule.name = "素材"
        XCTAssertEqual(model.plan.items.map(\.newName), ["素材 01.txt", "素材 02.txt"])
        XCTAssertEqual(model.summary, "会改 2 个文件的名字")
    }
}
