import CoreGraphics
import XCTest
@testable import Pop

final class ScrollStitcherTests: XCTestCase {
    private static let white: UInt32 = 0xFFFF_FFFF

    func testStitchesFramesAndKeepsTheStaticBarsOnce() throws {
        var random = Self.Random(seed: 1)
        let page = Self.page(height: 600, width: 60, random: &random)
        let header = (0..<20).map { _ in (0..<60).map { UInt32(0xFF00_00AA) | UInt32($0 % 7) << 8 } }
        let footer = (0..<16).map { _ in (0..<60).map { UInt32(0xFF00_AA00) | UInt32($0 % 5) } }
        func frame(_ top: Int) -> [[UInt32]] { header + Array(page[top..<(top + 200)]) + footer }

        var stitcher = try XCTUnwrap(ScrollStitcher(first: Self.image(frame(0))))
        var steps: [ScrollStitcher.Step] = []
        for top in [37, 81, 81, 150, 230, 300, 390, 400, 400] {
            steps.append(stitcher.add(try Self.image(frame(top))))
        }
        XCTAssertEqual(steps, [.appended(37), .appended(44), .unchanged, .appended(69), .appended(80), .appended(70),
                               .appended(90), .appended(10), .unchanged])
        XCTAssertEqual(stitcher.frames, 8)
        // 工具栏、底栏各只留一份，中间是完整的一页
        XCTAssertEqual(stitcher.height, 20 + 600 + 16)
        let result = try XCTUnwrap(stitcher.makeImage())
        XCTAssertEqual(try Self.rows(result), try Self.rows(Self.image(header + page + footer)))
    }

    func testPicksUpAgainAfterScrollingTooFast() throws {
        var random = Self.Random(seed: 2)
        let page = Array(repeating: Array(repeating: Self.white, count: 60), count: 30) + Self.page(height: 500, width: 60, random: &random)
        func frame(_ top: Int) -> [[UInt32]] { Array(page[top..<(top + 200)]) }

        var stitcher = try XCTUnwrap(ScrollStitcher(first: Self.image(frame(0))))
        var steps: [ScrollStitcher.Step] = []
        // 一下滚到 300：和上一屏没有重叠，这一屏不要；滚回来接上以后继续
        for top in [10, 25, 60, 300, 120, 200, 330] {
            steps.append(stitcher.add(try Self.image(frame(top))))
        }
        XCTAssertEqual(steps, [.appended(10), .appended(15), .appended(35), .lost, .appended(60), .appended(80), .appended(130)])
        XCTAssertEqual(try Self.rows(XCTUnwrap(stitcher.makeImage())), try Self.rows(Self.image(Array(page[0..<530]))))
    }

    func testIgnoresTheScrollBarAndSmallChanges() throws {
        var random = Self.Random(seed: 3)
        let page = Self.page(height: 900, width: 200, random: &random)
        // 滚动条的滑块画在右边，跟着滚动的位置上下移动
        func frame(_ top: Int, knob: Bool = true) -> [[UInt32]] {
            var rows = Array(page[top..<(top + 240)])
            if knob {
                let start = top * 240 / 900
                for row in start..<min(240, start + 60) {
                    for column in 188..<196 {
                        rows[row][column] = 0xFF88_8888
                    }
                }
            }
            return rows
        }
        var stitcher = try XCTUnwrap(ScrollStitcher(first: Self.image(frame(0, knob: false))))
        var steps: [ScrollStitcher.Step] = []
        for top in [20, 55, 90, 140, 200, 260, 330, 420, 500, 560, 600, 660] {
            steps.append(stitcher.add(try Self.image(frame(top))))
        }
        XCTAssertFalse(steps.contains(.lost))
        XCTAssertEqual(stitcher.height, 900)

        // 光标闪了一下：当作没滚
        var caret = frame(0, knob: false)
        for row in 100..<116 {
            caret[row][50] = 0xFF00_0000
            caret[row][51] = 0xFF00_0000
        }
        var still = try XCTUnwrap(ScrollStitcher(first: Self.image(frame(0, knob: false))))
        XCTAssertEqual(still.add(try Self.image(caret)), .unchanged)
    }

    func testStopsAtTheHeightLimit() throws {
        var random = Self.Random(seed: 4)
        let page = Self.page(height: 400, width: 60, random: &random)
        func frame(_ top: Int) -> [[UInt32]] { Array(page[top..<(top + 200)]) }
        var stitcher = try XCTUnwrap(ScrollStitcher(first: Self.image(frame(0)), maxHeight: 250))
        XCTAssertEqual(stitcher.add(try Self.image(frame(37))), .appended(37))
        XCTAssertEqual(stitcher.add(try Self.image(frame(81))), .full)
        XCTAssertEqual(stitcher.height, 237)
    }

    func testCutsTallImagesAtBlankRows() throws {
        var random = Self.Random(seed: 5)
        let page = Self.page(height: 5000, width: 40, random: &random)
        let image = try Self.image(page)
        let sections = ScrollStitcher.sections(of: image, maxHeight: 2400)
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.map(\.height).reduce(0, +), 5000)
        XCTAssertTrue(sections.allSatisfy { $0.height <= 2400 })
        // 每一段的最后一行都是空白：没有把一行字切开
        for section in sections.dropLast() {
            XCTAssertEqual(Set(try Self.rows(section).last ?? []), [Self.white])
        }
        XCTAssertEqual(ScrollStitcher.sections(of: try Self.image(Array(page[0..<300])), maxHeight: 2400).count, 1)
    }

    func testCardShowsAScrollablePreview() throws {
        var random = Self.Random(seed: 6)
        let image = try Self.image(Self.page(height: 1000, width: 900, random: &random))
        let card = try XCTUnwrap(ScrollStitcher.card(image, frameHeight: 400))
        XCTAssertEqual(card.title, "滚动截图")
        XCTAssertEqual(card.detail, "拼好了一张 900 × 1000 像素的长图，约 2.5 屏高；按住拖动预览图也能拖到别的 App 里")
        XCTAssertEqual(ScrollStitcher.card(image, frameHeight: 1000)?.detail, "没有滚动，只截了一屏（900 × 1000 像素）；按住拖动预览图也能拖到别的 App 里")
        XCTAssertEqual(ScrollStitcher.screensText(height: 1040, frameHeight: 1000), "1")
        XCTAssertEqual(ScrollStitcher.screensText(height: 12_300, frameHeight: 1000), "12")
        let png = try XCTUnwrap(card.image)
        XCTAssertEqual(card.buttons.count, 3)
        XCTAssertEqual(card.buttons[0].action, .copyImage(png))
        XCTAssertEqual(card.buttons[2].action, .recognizeImageText(png))
        // 预览缩到 720 像素宽，完整的图不缩
        let preview = try XCTUnwrap(card.imagePreview.flatMap { TextRecognizer.cgImage(from: $0) })
        XCTAssertEqual(preview.width, 720)
        XCTAssertEqual(preview.height, 800)
        XCTAssertEqual(TextRecognizer.cgImage(from: png)?.height, 1000)
    }

    // MARK: - 测试用的图片

    /// 固定种子的随机数，每次跑出来都一样
    private struct Random {
        var seed: UInt64

        mutating func next() -> UInt32 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt32(truncatingIfNeeded: seed >> 33)
        }
    }

    /// 一页「文字」：每 20 行里 14 行是杂色的字，6 行空白
    private static func page(height: Int, width: Int, random: inout Random) -> [[UInt32]] {
        let ink: [UInt32] = [0xFF11_1111, 0xFF22_2222, 0xFF33_3333, white]
        var rows: [[UInt32]] = []
        for row in 0..<height {
            if row % 20 < 14 {
                var line: [UInt32] = []
                for _ in 0..<width {
                    line.append(ink[Int(random.next() % 4)])
                }
                rows.append(line)
            } else {
                rows.append(Array(repeating: white, count: width))
            }
        }
        return rows
    }

    /// 一行一行的像素（RGBA，不透明）拼成 sRGB 图片
    private static func image(_ rows: [[UInt32]]) throws -> CGImage {
        let width = rows.first?.count ?? 0
        var pixels: [UInt32] = []
        for row in rows {
            pixels += row
        }
        let data = pixels.withUnsafeBytes { Data($0) }
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGImage(width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                     space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    /// 图片读回一行一行的像素
    private static func rows(_ image: CGImage) throws -> [[UInt32]] {
        let pixels = try XCTUnwrap(ScrollStitcher.rgba(image, space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))))
        var rows: [[UInt32]] = []
        for row in 0..<image.height {
            rows.append(Array(pixels[(row * image.width)..<((row + 1) * image.width)]))
        }
        return rows
    }
}
