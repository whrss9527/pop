import AppKit
import Carbon.HIToolbox
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pop

final class KeyComboTests: XCTestCase {
    func testRecordingRules() throws {
        let optionT = try XCTUnwrap(KeyCombo(keyCode: UInt32(kVK_ANSI_T), flags: [.option]))
        XCTAssertEqual(optionT.display, "⌥T")
        XCTAssertEqual(optionT.modifiers, UInt32(optionKey))
        XCTAssertEqual(KeyCombo(keyCode: UInt32(kVK_ANSI_S), flags: [.command, .shift, .control])?.display, "⌃⇧⌘S")
        XCTAssertEqual(KeyCombo(keyCode: UInt32(kVK_Space), flags: [.option])?.display, "⌥Space")
        // 功能键可以单独用，普通按键至少要带 ⌘、⌥、⌃ 中的一个
        XCTAssertEqual(KeyCombo(keyCode: UInt32(kVK_F5), flags: [])?.display, "F5")
        XCTAssertNil(KeyCombo(keyCode: UInt32(kVK_ANSI_A), flags: []))
        XCTAssertNil(KeyCombo(keyCode: UInt32(kVK_ANSI_A), flags: [.shift]))
        // 只按了修饰键
        XCTAssertNil(KeyCombo(keyCode: UInt32(kVK_Command), flags: [.command]))
        // 和预设的快捷键比较
        XCTAssertEqual(HotKeyPreset.optionSpace.keyCombo, KeyCombo(keyCode: UInt32(kVK_Space), flags: [.option]))
        XCTAssertNil(HotKeyPreset.none.keyCombo)
    }

    func testSettingsKeepOneFunctionPerShortcut() throws {
        let optionT = KeyCombo(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(optionKey))
        var settings = AppSettings()
        settings.setHotKey(optionT, for: BuiltinPluginID.translate)
        XCTAssertEqual(settings.hotKey(for: BuiltinPluginID.translate), optionT)
        // 同一个组合键给了别的功能：从原来的功能上拿掉
        settings.setHotKey(optionT, for: BuiltinPluginID.search)
        XCTAssertNil(settings.hotKey(for: BuiltinPluginID.translate))
        XCTAssertEqual(settings.hotKey(for: BuiltinPluginID.search), optionT)
        XCTAssertEqual(settings.pluginHotKeys.count, 1)
        // 卸载功能时一起清掉
        settings.setInstalled(BuiltinPluginID.search, false)
        XCTAssertTrue(settings.pluginHotKeys.isEmpty)

        settings.setHotKey(optionT, for: BuiltinPluginID.screenshotTranslate)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.pluginHotKeys, settings.pluginHotKeys)
        // 坏掉的一项跳过，其他照常读出来
        let lossy = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"pluginHotKeys": [{"pluginID": "translate"}, {"pluginID": "search", "key": {"keyCode": 17, "modifiers": 2048}}]}"#.utf8))
        XCTAssertEqual(lossy.pluginHotKeys.map(\.pluginID), ["search"])
    }
}

final class WindowLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    func testHalvesThirdsAndMaximize() {
        XCTAssertEqual(WindowLayout.leftHalf.frame(for: window, in: screen), CGRect(x: 0, y: 0, width: 720, height: 875))
        XCTAssertEqual(WindowLayout.rightHalf.frame(for: window, in: screen), CGRect(x: 720, y: 0, width: 720, height: 875))
        // AppKit 坐标 y 向上：上半屏的 y 更大
        XCTAssertEqual(WindowLayout.topHalf.frame(for: window, in: screen), CGRect(x: 0, y: 437, width: 1440, height: 438))
        XCTAssertEqual(WindowLayout.bottomHalf.frame(for: window, in: screen), CGRect(x: 0, y: 0, width: 1440, height: 438))
        XCTAssertEqual(WindowLayout.leftThird.frame(for: window, in: screen), CGRect(x: 0, y: 0, width: 480, height: 875))
        XCTAssertEqual(WindowLayout.centerThird.frame(for: window, in: screen), CGRect(x: 480, y: 0, width: 480, height: 875))
        XCTAssertEqual(WindowLayout.rightThird.frame(for: window, in: screen), CGRect(x: 960, y: 0, width: 480, height: 875))
        XCTAssertEqual(WindowLayout.maximize.frame(for: window, in: screen), screen)
    }

    func testCenterKeepsSizeAndFits() {
        XCTAssertEqual(WindowLayout.center.frame(for: window, in: screen), CGRect(x: 320, y: 138, width: 800, height: 600))
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        XCTAssertEqual(WindowLayout.center.frame(for: huge, in: screen), screen)
        // 屏幕不在原点（副屏）
        let secondary = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        XCTAssertEqual(WindowLayout.center.frame(for: window, in: secondary), CGRect(x: 1440 + 560, y: -200 + 228, width: 800, height: 600))
    }

    func testMovingToAnotherDisplay() {
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1055)
        let moved = WindowLayout.moved(window, from: screen, to: secondary)
        XCTAssertEqual(moved.size, window.size)
        XCTAssertTrue(secondary.contains(moved))
        XCTAssertEqual(moved.minX, 1440 + (100.0 / 1440 * 1920).rounded())
        // 放不下时缩小
        let small = CGRect(x: 0, y: 0, width: 640, height: 480)
        XCTAssertEqual(WindowLayout.moved(window, from: screen, to: small).size, CGSize(width: 640, height: 480))
        XCTAssertEqual(WindowLayout.screenIndex(for: window, among: [screen, secondary]), 0)
        XCTAssertEqual(WindowLayout.screenIndex(for: CGRect(x: 1400, y: 0, width: 800, height: 600), among: [screen, secondary]), 1)
        XCTAssertNil(WindowLayout.screenIndex(for: CGRect(x: -5000, y: 0, width: 10, height: 10), among: [screen, secondary]))
    }

    @MainActor
    func testKeyboardChoices() throws {
        func key(_ code: Int, _ characters: String = "") throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                           isARepeat: false, keyCode: UInt16(code)))
        }
        XCTAssertEqual(WindowLayoutCardView.layout(for: try key(kVK_LeftArrow)), .leftHalf)
        XCTAssertEqual(WindowLayoutCardView.layout(for: try key(kVK_Return, "\r")), .maximize)
        XCTAssertEqual(WindowLayoutCardView.layout(for: try key(kVK_ANSI_2, "2")), .centerThird)
        XCTAssertNil(WindowLayoutCardView.layout(for: try key(kVK_ANSI_Q, "q")))
    }
}

final class ImageConverterTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "pop-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// 生成一张 40×20 的 PNG
    private func makePNG(named name: String) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let image = try XCTUnwrap(context.makeImage())
        let url = folder.appending(path: name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func pixelSize(_ url: URL) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return CGSize(width: try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
                      height: try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    func testConversionsLandNextToTheOriginal() throws {
        let original = try makePNG(named: "图.png")
        let jpeg = try ImageConverter.convert(original, .jpeg)
        XCTAssertEqual(jpeg.lastPathComponent, "图.jpg")
        XCTAssertEqual(try pixelSize(jpeg), CGSize(width: 40, height: 20))

        let half = try ImageConverter.convert(original, .halfSize)
        XCTAssertEqual(half.lastPathComponent, "图 缩小.png")
        XCTAssertEqual(try pixelSize(half), CGSize(width: 20, height: 10))

        // 同名文件已经存在（包括原图自己）时加编号，不覆盖
        let png = try ImageConverter.convert(original, .png)
        XCTAssertEqual(png.lastPathComponent, "图 2.png")
        let compressed = try ImageConverter.convert(original, .compress)
        XCTAssertEqual(compressed.lastPathComponent, "图 压缩.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path(percentEncoded: false)))

        XCTAssertThrowsError(try ImageConverter.convert(folder.appending(path: "不存在.png"), .png))
        XCTAssertEqual(ImageInfo.rows(for: original).first?.value, "40 × 20")
    }

    func testRotateAndFlip() throws {
        // 左红右蓝的 2×1 图片
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
        let url = folder.appending(path: "方向.png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        func isRed(_ file: URL, _ x: Int, _ y: Int) throws -> Bool {
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: file)))
            let color = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
            return color.redComponent > 0.8 && color.blueComponent < 0.2
        }
        // 向右转（顺时针）：红的到上面
        let right = try ImageConverter.convert(url, .rotateRight)
        XCTAssertEqual(right.lastPathComponent, "方向 向右转.png")
        XCTAssertEqual(try pixelSize(right), CGSize(width: 1, height: 2))
        XCTAssertTrue(try isRed(right, 0, 0))
        // 向左转：红的到下面
        let left = try ImageConverter.convert(url, .rotateLeft)
        XCTAssertEqual(try pixelSize(left), CGSize(width: 1, height: 2))
        XCTAssertTrue(try isRed(left, 0, 1))
        // 左右翻转：红的到右边
        let flipped = try ImageConverter.convert(url, .flipHorizontal)
        XCTAssertEqual(flipped.lastPathComponent, "方向 翻转.png")
        XCTAssertTrue(try isRed(flipped, 1, 0))
        XCTAssertFalse(try isRed(flipped, 0, 0))
    }

    @MainActor
    func testPluginOffersEveryOperation() async throws {
        let original = try makePNG(named: "a.png")
        let outcome = await ImageConvertPlugin().run(ContentClassifier.classify(.files([original])),
                                                     context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        // 截图里没有位置和拍摄信息，不给去掉的按钮；一张小图可以复制成 data URI
        XCTAssertEqual(card.buttons.map(\.title), ImageConverter.Operation.allCases.filter {
            $0 != .removeLocation && $0 != .removeMetadata
        }.map(\.title) + ["复制为 data URI"])
        XCTAssertEqual(card.buttons.first?.action, .convertImages([original], .png))
        guard case .copy(let uri) = card.buttons.last?.action else { return XCTFail("最后一个按钮应该是复制 data URI") }
        XCTAssertTrue(uri.hasPrefix("data:image/png;base64,iVBORw0KGgo"), String(uri.prefix(40)))
    }
}
