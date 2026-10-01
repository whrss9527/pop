import AppKit
import XCTest
@testable import Pop

@MainActor
final class WindowPiPTests: XCTestCase {
    private func item(_ id: CGWindowID, pid: pid_t = 100, app: String = "Safari", title: String = "",
                      frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600), layer: Int = 0, onScreen: Bool = true) -> PiPWindows.Item {
        PiPWindows.Item(id: id, pid: pid, appName: app, title: title, frame: frame, layer: layer, isOnScreen: onScreen)
    }

    // MARK: - 能放进小窗的窗口

    func testCandidatesAreNormalVisibleWindowsFrontToBack() {
        let items = [
            item(1, title: "后面的"),
            item(2, layer: 25),
            item(3, pid: 42, app: "Pop"),
            item(4, frame: CGRect(x: 0, y: 0, width: 100, height: 300)),
            item(5, onScreen: false),
            item(6, title: "前面的"),
            item(7, title: "不在顺序里"),
        ]
        let candidates = PiPWindows.candidates(items, ownPID: 42, order: [6, 2, 3, 1])
        // 浮窗、Pop 自己的、太小的、不在屏幕上的都不要；按从前到后排，不在顺序里的排最后
        XCTAssertEqual(candidates.map(\.id), [6, 1, 7])
    }

    func testWindowUnderThePointer() {
        let front = item(1, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        let back = item(2, frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        XCTAssertEqual(PiPWindows.item(at: CGPoint(x: 200, y: 200), in: [front, back])?.id, 1)
        XCTAssertEqual(PiPWindows.item(at: CGPoint(x: 900, y: 700), in: [front, back])?.id, 2)
        XCTAssertNil(PiPWindows.item(at: CGPoint(x: 1200, y: 10), in: [front, back]))
        // AppKit 坐标（左下角为原点）和 CG 坐标（左上角为原点）互换
        XCTAssertEqual(PiPWindows.cgPoint(fromAppKit: CGPoint(x: 10, y: 900), primaryScreenHeight: 1000), CGPoint(x: 10, y: 100))
        XCTAssertEqual(PiPWindows.appKitRect(fromCG: CGRect(x: 0, y: 100, width: 400, height: 300), primaryScreenHeight: 1000),
                       CGRect(x: 0, y: 600, width: 400, height: 300))
    }

    func testDisplayTitle() {
        XCTAssertEqual(item(1, app: "Safari", title: "发布会直播").displayTitle, "Safari — 发布会直播")
        XCTAssertEqual(item(1, app: "访达", title: "  ").displayTitle, "访达")
        XCTAssertEqual(item(1, app: "备忘录", title: "备忘录").displayTitle, "备忘录")
    }

    // MARK: - 小窗的大小和位置

    func testSizeKeepsTheWindowShape() {
        XCTAssertEqual(PiPLayout.size(for: CGSize(width: 1600, height: 900), longSide: 360), CGSize(width: 360, height: 203))
        XCTAssertEqual(PiPLayout.size(for: CGSize(width: 600, height: 1200), longSide: 360), CGSize(width: 180, height: 360))
        XCTAssertEqual(PiPLayout.size(for: .zero, longSide: 360), CGSize(width: 360, height: 360))
        XCTAssertEqual(PiPLayout.scrolled(360, by: 40), 400)
        XCTAssertEqual(PiPLayout.scrolled(200, by: -100), 160)
        XCTAssertEqual(PiPLayout.scrolled(900, by: 200), 960)
        XCTAssertEqual(PiPLayout.savedLongSide(0), 360)
        XCTAssertEqual(PiPLayout.savedLongSide(520), 520)
        XCTAssertTrue(PiPLayout.captureSize(for: CGSize(width: 360, height: 203), scale: 2) == (720, 406))
        XCTAssertTrue(PiPLayout.captureSize(for: CGSize(width: 10, height: 10), scale: 1) == (64, 64))
    }

    func testNewWindowsStackFromTheBottomRightCorner() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let size = CGSize(width: 360, height: 203)
        let first = PiPLayout.defaultFrame(size: size, in: visible, occupied: [])
        XCTAssertEqual(first, CGRect(x: 1060, y: 20, width: 360, height: 203))
        // 第二个摞在上面，第三个再往上
        let second = PiPLayout.defaultFrame(size: size, in: visible, occupied: [first])
        XCTAssertEqual(second, CGRect(x: 1060, y: 235, width: 360, height: 203))
        let third = PiPLayout.defaultFrame(size: size, in: visible, occupied: [first, second])
        XCTAssertEqual(third, CGRect(x: 1060, y: 450, width: 360, height: 203))
        // 一列摞满了往左挪一列
        let fourth = PiPLayout.defaultFrame(size: size, in: visible, occupied: [first, second, third,
                                                                                  CGRect(x: 1060, y: 665, width: 360, height: 203)])
        XCTAssertEqual(fourth, CGRect(x: 688, y: 20, width: 360, height: 203))
        // 屏幕太小放不下：放在右下角
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertEqual(PiPLayout.defaultFrame(size: size, in: tiny, occupied: []), CGRect(x: -80, y: 20, width: 360, height: 203))
    }

    func testResizeKeepsTheCenterOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frame = CGRect(x: 1060, y: 20, width: 360, height: 203)
        // 变大：中心不动，超出屏幕的挪回来
        let bigger = PiPLayout.resized(frame, longSide: 520, within: visible)
        XCTAssertEqual(bigger.size, CGSize(width: 520, height: 293))
        XCTAssertEqual(bigger.maxX, 1440)
        XCTAssertEqual(bigger.minY, 0)
        let smaller = PiPLayout.resized(CGRect(x: 400, y: 300, width: 360, height: 203), longSide: 240, within: visible)
        XCTAssertEqual(smaller, CGRect(x: 460, y: 334, width: 240, height: 135))
    }

    // MARK: - 选窗口的卡片

    func testChooserPutsTheWindowUnderThePointerFirst() {
        var chosen: [CGWindowID] = []
        let items = (1...5).map { item(CGWindowID($0), title: "窗口 \($0)") }
        let model = PiPChooserModel(items: items, under: 3, openCount: 1, showing: [5], icon: { _ in nil })
        model.onChoose = { chosen.append($0.id) }
        XCTAssertEqual(model.items.map(\.id), [3, 1, 2, 4, 5])
        XCTAssertEqual(model.selection, 3)
        XCTAssertEqual(model.openCount, 1)
        XCTAssertTrue(model.showing.contains(5))
        // 两列：左右换一个，上下换一行，到头停住
        model.move(1)
        XCTAssertEqual(model.selection, 1)
        model.move(PiPChooserModel.columns)
        XCTAssertEqual(model.selection, 4)
        model.move(PiPChooserModel.columns)
        XCTAssertEqual(model.selection, 5)
        model.move(-10)
        XCTAssertEqual(model.selection, 3)
        model.choose()
        model.choose(items[1])
        XCTAssertEqual(chosen, [3, 2])
        XCTAssertEqual(model.selection, 2)
        // 指针下没有窗口：按原来的顺序，选第一个
        let plain = PiPChooserModel(items: items, under: nil, icon: { _ in nil })
        XCTAssertEqual(plain.items.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertEqual(plain.selection, 1)
        XCTAssertNil(PiPChooserModel(items: [], under: nil, icon: { _ in nil }).selectedItem)
    }

    func testChooserKeys() throws {
        var chosen: CGWindowID?
        let model = PiPChooserModel(items: (1...4).map { item(CGWindowID($0)) }, under: nil, icon: { _ in nil })
        model.onChoose = { chosen = $0.id }
        func key(_ code: UInt16) throws -> Bool {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                       context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            return model.handleKey(event)
        }
        XCTAssertTrue(try key(124))
        XCTAssertTrue(try key(125))
        XCTAssertEqual(model.selection, 4)
        XCTAssertTrue(try key(126))
        XCTAssertEqual(model.selection, 2)
        XCTAssertFalse(try key(0))
        XCTAssertTrue(try key(36))
        XCTAssertEqual(chosen, 2)
    }

    // MARK: - 插件和演示

    func testPluginAndDemo() throws {
        XCTAssertTrue(WindowPiPPlugin().info.canHandle(.empty))
        XCTAssertEqual(Set(PictureInPicture.defaultsKeys), Set(PluginCatalog.packages.first { $0.id == "windowPiP" }?.defaultsKeys ?? []))
        let demo = WindowPiPPlugin.demoModel()
        XCTAssertEqual(demo.items.first?.displayTitle, "FaceTime — 产品周会")
        XCTAssertEqual(demo.thumbnails.count, 4)
        let meeting = try XCTUnwrap(WindowPiPPlugin.demoMeeting())
        XCTAssertEqual(meeting.width, 960)
        XCTAssertNotNil(WindowPiPPlugin.demoVideo())
        XCTAssertNotNil(WindowPiPPlugin.demoTerminal())

        // 演示的小窗放在屏幕右下角，关掉全部以后没有了
        let screen = try XCTUnwrap(NSScreen.main)
        let pip = PictureInPicture.shared
        let frame = pip.showForDemo(image: meeting, title: "产品周会", on: screen)
        XCTAssertEqual(pip.count, 1)
        XCTAssertEqual(frame.maxX, screen.visibleFrame.maxX - PiPLayout.margin, accuracy: 0.5)
        XCTAssertEqual(frame.width / frame.height, 960.0 / 540.0, accuracy: 0.01)
        pip.closeAll()
        XCTAssertEqual(pip.count, 0)
    }
}
