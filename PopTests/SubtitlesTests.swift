import XCTest
@testable import Pop

final class SubtitlesTests: XCTestCase {
    private typealias Cue = SubtitleTools.Cue
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-subtitles-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testReadsTimes() throws {
        XCTAssertEqual(try XCTUnwrap(SubtitleTools.seconds("01:02:03,456")), 3723.456, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SubtitleTools.seconds("02:03.5")), 123.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SubtitleTools.seconds("0:00:01.25")), 1.25, accuracy: 0.0001)
        XCTAssertNil(SubtitleTools.seconds("1:61:00"))
        XCTAssertNil(SubtitleTools.seconds("abc"))
        XCTAssertNil(SubtitleTools.timing("00:00:01,000 -> 00:00:02,000"))
        XCTAssertEqual(SubtitleTools.timestamp(3723.4567), "01:02:03,457")
        XCTAssertEqual(SubtitleTools.timestamp(1.5, separator: "."), "00:00:01.500")
        XCTAssertEqual(SubtitleTools.lyricTime(3723.456), "62:03.46")
    }

    func testParsesSRTWithIndexesTagsAndMissingBlankLines() {
        let text = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>你好</i>\r\n世界\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000 X1:100\r\nSecond\r\n3\r\n00:00:05,000 --> 00:00:06,000\r\nThird\r\n"
        XCTAssertEqual(SubtitleTools.parse(text, format: .srt), [
            Cue(start: 1, end: 2.5, text: "<i>你好</i>\n世界"),
            Cue(start: 3, end: 4, text: "Second"),
            Cue(start: 5, end: 6, text: "Third"),
        ])
    }

    func testParsesWebVTTWithHeaderNotesAndIdentifiers() {
        let text = """
        WEBVTT
        Kind: captions

        NOTE 这是注释

        intro
        00:01.000 --> 00:02.000 align:start
        Hello <c.yellow>there</c>

        NOTE 中间的注释

        00:00:03.500 --> 00:00:05.000
        Second line
        """
        XCTAssertEqual(SubtitleTools.parse(text, format: .vtt), [
            Cue(start: 1, end: 2, text: "Hello <c.yellow>there</c>"),
            Cue(start: 3.5, end: 5, text: "Second line"),
        ])
        XCTAssertEqual(SubtitleTools.format(of: URL(fileURLWithPath: "/tmp/a.txt"), text: text), .vtt)
    }

    func testParsesASSDialogue() {
        let text = """
        [Script Info]
        Title: 示例

        [V4+ Styles]
        Format: Name, Fontname, Fontsize
        Style: Default,Arial,20

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.50,Default,,0,0,0,,{\\an8}你好，世界\\N{\\fs12}Hello, world
        Comment: 0,0:00:04.00,0:00:05.00,Default,,0,0,0,,注释
        Dialogue: 0,0:00:00.50,0:00:01.00,Default,,0,0,0,,开头
        """
        XCTAssertEqual(SubtitleTools.parse(text, format: .ass), [
            Cue(start: 0.5, end: 1, text: "开头"),
            Cue(start: 1, end: 3.5, text: "你好，世界\nHello, world"),
        ])
        XCTAssertEqual(SubtitleTools.format(of: URL(fileURLWithPath: "/tmp/a.ssa"), text: ""), .ass)
    }

    func testParsesLyricsWithOffsetAndWordTimes() {
        let text = """
        [ti:歌]
        [offset:500]
        [00:01.00][00:10.00]副歌
        [00:05.50]<00:05.50>第<00:05.80>二句
        [00:08.00]
        """
        XCTAssertEqual(SubtitleTools.parse(text, format: .lrc), [
            Cue(start: 0.5, end: 5, text: "副歌"),
            Cue(start: 5, end: 7.5, text: "第二句"),
            Cue(start: 9.5, end: 13.5, text: "副歌"),
        ])
    }

    func testRetimesCleansAndMerges() {
        let cues = [Cue(start: 1, end: 2.5, text: "<i>你好</i> [笑声]\n(MUSIC)"), Cue(start: 3, end: 4, text: "[音乐]"), Cue(start: 5, end: 6, text: "<b>好</b>")]
        // 推后、提前到 0 之前的去掉
        XCTAssertEqual(SubtitleTools.retime(cues, shift: 1.5).map(\.start), [2.5, 4.5, 6.5])
        XCTAssertEqual(SubtitleTools.retime(cues, shift: -2).map(\.start), [0, 1, 3])
        XCTAssertEqual(SubtitleTools.retime(cues, shift: -2).first?.end, 0.5)
        XCTAssertEqual(SubtitleTools.retime(cues, shift: -4.5).count, 1)
        let slower = SubtitleTools.retime(cues, shift: 0, rate: .pal25to23)
        XCTAssertEqual(slower[2].start, 5 * 25 / 23.976, accuracy: 0.0001)
        XCTAssertEqual(SubtitleTools.clean(cues, tags: true, descriptions: false).map(\.text), ["你好 [笑声]\n(MUSIC)", "[音乐]", "好"])
        XCTAssertEqual(SubtitleTools.clean(cues, tags: true, descriptions: true).map(\.text), ["你好", "好"])
        XCTAssertEqual(SubtitleTools.clean(cues, tags: false, descriptions: false), cues)

        let chinese = [Cue(start: 1, end: 2.5, text: "你好\n世界"), Cue(start: 3, end: 4, text: "第二句")]
        let english = [Cue(start: 1.1, end: 2.4, text: "Hello world"), Cue(start: 3, end: 4.2, text: "Second"), Cue(start: 10, end: 11, text: "Alone")]
        XCTAssertEqual(SubtitleTools.merge(chinese, english), [
            Cue(start: 1, end: 2.5, text: "你好 世界\nHello world"),
            Cue(start: 3, end: 4, text: "第二句\nSecond"),
            Cue(start: 10, end: 11, text: "Alone"),
        ])
        XCTAssertEqual(SubtitleTools.mergedName(URL(fileURLWithPath: "/tmp/电影.zh.srt"), URL(fileURLWithPath: "/tmp/电影.en.vtt")), "电影 双语")
        XCTAssertEqual(SubtitleTools.mergedName(URL(fileURLWithPath: "/tmp/中文.srt"), URL(fileURLWithPath: "/tmp/English.srt")), "中文 双语")
    }

    func testRendersEveryFormat() {
        let cues = [Cue(start: 1, end: 2.5, text: "你好\n世界"), Cue(start: 61.25, end: 63, text: "Second")]
        XCTAssertEqual(SubtitleTools.render(cues, as: .srt), "1\n00:00:01,000 --> 00:00:02,500\n你好\n世界\n\n2\n00:01:01,250 --> 00:01:03,000\nSecond\n")
        XCTAssertEqual(SubtitleTools.render(cues, as: .vtt), "WEBVTT\n\n00:00:01.000 --> 00:00:02.500\n你好\n世界\n\n00:01:01.250 --> 00:01:03.000\nSecond\n")
        XCTAssertEqual(SubtitleTools.render(cues, as: .lrc), "[00:01.00]你好 世界\n[01:01.25]Second\n")
        XCTAssertEqual(SubtitleTools.render(cues, as: .txt), "你好 世界\nSecond\n")
        // 写出来的再读回去一样
        XCTAssertEqual(SubtitleTools.parse(SubtitleTools.render(cues, as: .srt), format: .srt), cues)
        XCTAssertEqual(SubtitleTools.parse(SubtitleTools.render(cues, as: .vtt), format: .vtt), cues)
    }

    func testDecodesGBKAndUTF16() throws {
        let text = "1\n00:00:01,000 --> 00:00:02,000\n大家好，欢迎来到今天的发布会，我们先看一下这一年做了什么\n"
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let decoded = try XCTUnwrap(SubtitleTools.decode(try XCTUnwrap(text.data(using: gb18030))))
        XCTAssertEqual(decoded.text, text)
        XCTAssertEqual(decoded.encoding, "GBK")
        XCTAssertEqual(SubtitleTools.decode(try XCTUnwrap(text.data(using: .utf16)))?.text, text)
        XCTAssertEqual(SubtitleTools.decode(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))?.encoding, "UTF-8")
    }

    @MainActor
    func testShiftsTheOriginalFileAndUndoes() throws {
        let url = folder.appending(path: "发布会.srt")
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let original = try XCTUnwrap("1\r\n00:00:01,000 --> 00:00:02,000\r\n<i>大家好，欢迎来到今天的发布会</i>\r\n".data(using: gb18030))
        try original.write(to: url)
        let source = try XCTUnwrap(SubtitlesModel.load(url))
        XCTAssertEqual(source.encoding, "GBK")
        let model = SubtitlesModel(sources: [source])
        XCTAssertEqual(model.output, .srt)
        XCTAssertEqual(model.describe(source), "SRT · 1 句 · 0:01 – 0:02 · GBK")
        model.shift = 1.5
        XCTAssertEqual(model.shiftText, "推后 1.5 秒")
        model.stripTags = true
        XCTAssertEqual(model.preview, [Cue(start: 2.5, end: 3.5, text: "大家好，欢迎来到今天的发布会")])
        model.save()
        XCTAssertEqual(model.phase, .saved(files: [url], replaced: [url]))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "1\n00:00:02,500 --> 00:00:03,500\n大家好，欢迎来到今天的发布会\n")
        XCTAssertEqual(model.savedMessage, "改好了「发布会.srt」，存成 UTF-8")
        model.undo()
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(model.phase, .editing)

        // 换格式：另存一份，原文件不动
        model.shift = -0.5
        XCTAssertEqual(model.shiftText, "提前 0.5 秒")
        model.output = .vtt
        model.save()
        let copy = folder.appending(path: "发布会.vtt")
        XCTAssertEqual(model.phase, .saved(files: [copy], replaced: []))
        XCTAssertEqual(try String(contentsOf: copy, encoding: .utf8), "WEBVTT\n\n00:00:00.500 --> 00:00:01.500\n大家好，欢迎来到今天的发布会\n")
        XCTAssertEqual(try Data(contentsOf: url), original)
        model.undo()
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path(percentEncoded: false)))
    }

    @MainActor
    func testMergesTwoFilesIntoABilingualCopy() throws {
        let chinese = folder.appending(path: "发布会.zh.srt")
        let english = folder.appending(path: "发布会.en.vtt")
        try "1\n00:00:01,000 --> 00:00:03,000\n大家好\n".write(to: chinese, atomically: true, encoding: .utf8)
        try "WEBVTT\n\n00:01.100 --> 00:02.900\nHello everyone\n".write(to: english, atomically: true, encoding: .utf8)
        let model = SubtitlesModel(sources: try [chinese, english].map { try XCTUnwrap(SubtitlesModel.load($0)) })
        XCTAssertTrue(model.isMerging)
        XCTAssertEqual(model.preview.first?.text, "大家好\nHello everyone")
        model.topIndex = 1
        XCTAssertEqual(model.preview.first?.text, "Hello everyone\n大家好")
        model.save()
        let merged = folder.appending(path: "发布会 双语.srt")
        XCTAssertEqual(model.phase, .saved(files: [merged], replaced: []))
        XCTAssertEqual(try String(contentsOf: merged, encoding: .utf8), "1\n00:00:01,100 --> 00:00:02,900\nHello everyone\n大家好\n")
        // 不合成：两份各自处理
        model.merge = false
        model.output = .txt
        XCTAssertEqual(model.outputs.map(\.url.lastPathComponent), ["发布会.zh.txt", "发布会.en.txt"])
        XCTAssertNil(SubtitlesModel.load(folder.appending(path: "没有这个.srt")))
    }

    @MainActor
    func testDemoAndPlugin() {
        let model = SubtitlesModel(sources: SubtitlesPlugin.demoSources())
        XCTAssertEqual(model.sources.map(\.cues.count), [3, 3])
        XCTAssertTrue(model.isMerging)
        XCTAssertEqual(model.preview.count, 3)
        XCTAssertEqual(model.preview.first?.text, "大家好，欢迎来到今天的发布会\nHello everyone, welcome to today's keynote.")

        let plugin = SubtitlesPlugin().info
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/电影.srt")]))))
        XCTAssertTrue(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/电影.ASS")]))))
        XCTAssertFalse(plugin.canHandle(ContentClassifier.classify(.files([URL(fileURLWithPath: "/tmp/说明.txt")]))))
        XCTAssertFalse(plugin.canHandle(.empty))
    }
}
