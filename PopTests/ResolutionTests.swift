import CoreGraphics
import XCTest
@testable import Pop

final class ResolutionTests: XCTestCase {
    private func mode(_ id: Int32, _ width: Int, _ height: Int, scale: Int = 2, rate: Double = 60, isDefault: Bool = false) -> DisplayModes.Mode {
        DisplayModes.Mode(ioID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale, refreshRate: rate,
                          isDefault: isDefault)
    }

    private func display(_ id: CGDirectDisplayID, _ name: String, builtIn: Bool = false, main: Bool = false, current: DisplayModes.Mode? = nil,
                         modes: [DisplayModes.Mode] = []) -> DisplayModes.Display {
        DisplayModes.Display(id: id, name: name, isBuiltIn: builtIn, isMain: main, bounds: CGRect(x: CGFloat(id) * 2000, y: 0, width: 1920, height: 1080),
                             current: current, modes: modes)
    }

    func testChoicesGroupSizesAndPreferHiDPI() {
        let modes = [
            mode(1, 1512, 982, rate: 120, isDefault: true), mode(2, 1512, 982, rate: 60, isDefault: true), mode(3, 1512, 982, scale: 1, rate: 120),
            mode(4, 1800, 1169, rate: 60), mode(5, 1800, 1169, rate: 120), mode(6, 1147, 745, rate: 120),
            mode(7, 1024, 768, scale: 1), mode(8, 3600, 2338, scale: 1),
        ]
        let current = modes[1]
        let choices = DisplayModes.choices(modes, current: current)
        // 从小到大，每个大小一行
        XCTAssertEqual(choices.map { DisplayModes.sizeText($0.mode) }, ["1024 × 768", "1147 × 745", "1512 × 982", "1800 × 1169", "3600 × 2338"])
        // 正在用的大小就用现在的模式；别的大小挑 HiDPI、刷新率和现在一样的
        XCTAssertEqual(choices[2].mode, current)
        XCTAssertEqual(choices[3].mode.ioID, 4)
        XCTAssertEqual(choices.map(\.isDefault), [false, false, true, false, false])
        // 没有 HiDPI、又比屏幕的像素少的会发虚；原生分辨率不算
        XCTAssertEqual(choices.map(\.isBlurry), [true, false, false, false, false])

        // 没有 HiDPI 的显示器上都不算发虚
        let plain = [mode(1, 1920, 1080, scale: 1), mode(2, 1280, 720, scale: 1)]
        XCTAssertEqual(DisplayModes.choices(plain, current: plain[0]).map(\.isBlurry), [false, false])
        // 正在用的模式不在列表里也列出来
        let missing = mode(9, 1680, 1050, scale: 1)
        XCTAssertTrue(DisplayModes.choices(plain, current: missing).contains { $0.mode == missing })
        XCTAssertEqual(DisplayModes.choices([], current: nil), [])
    }

    func testBestModePrefersHiDPIAndTheCurrentRate() {
        let group = [mode(1, 1800, 1169, scale: 1, rate: 120), mode(2, 1800, 1169, rate: 60), mode(3, 1800, 1169, rate: 120)]
        XCTAssertEqual(DisplayModes.best(group, current: mode(9, 1512, 982, rate: 60))?.ioID, 2)
        XCTAssertEqual(DisplayModes.best(group, current: mode(9, 1512, 982, rate: 120))?.ioID, 3)
        // 不知道现在用的哪个：HiDPI 里刷新率最高的
        XCTAssertEqual(DisplayModes.best(group, current: nil)?.ioID, 3)
        XCTAssertNil(DisplayModes.best([], current: nil))
    }

    func testRatesOfTheCurrentSize() {
        let current = mode(1, 1512, 982, rate: 120)
        let modes = [current, mode(2, 1512, 982, rate: 60), mode(3, 1512, 982, rate: 59.94), mode(4, 1512, 982, scale: 1, rate: 50),
                     mode(5, 1800, 1169, rate: 48), mode(6, 1512, 982, rate: 60)]
        // 一样大、一样清楚的，从高到低，重复的只要一个
        XCTAssertEqual(DisplayModes.rates(modes, current: current).map(\.ioID), [1, 2, 3])
        // 读不出刷新率的显示器不让选
        XCTAssertEqual(DisplayModes.rates([mode(1, 1440, 900, rate: 0)], current: mode(1, 1440, 900, rate: 0)), [])
        XCTAssertEqual(DisplayModes.rates(modes, current: nil), [])

        XCTAssertEqual(DisplayModes.rateText(120), "120 Hz")
        XCTAssertEqual(DisplayModes.rateText(60.0001), "60 Hz")
        XCTAssertEqual(DisplayModes.rateText(59.94), "59.94 Hz")
        XCTAssertEqual(DisplayModes.rateText(47.952), "47.95 Hz")
        XCTAssertEqual(DisplayModes.sizeText(current), "1512 × 982")
        XCTAssertTrue(current.same(as: mode(1, 1512, 982, rate: 120, isDefault: true)))
        XCTAssertFalse(current.same(as: mode(1, 1512, 982, rate: 60)))
    }

    func testMakingADisplayMainMovesEveryOrigin() {
        let bounds: [CGDirectDisplayID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1512, height: 982),
            2: CGRect(x: 1512, y: -300, width: 2560, height: 1440),
            3: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        ]
        let origins = DisplayModes.origins(makingMain: 2, bounds: bounds)
        XCTAssertEqual(origins?[2], .zero)
        XCTAssertEqual(origins?[1], CGPoint(x: -1512, y: 300))
        XCTAssertEqual(origins?[3], CGPoint(x: -3432, y: 300))
        XCTAssertNil(DisplayModes.origins(makingMain: 9, bounds: bounds))
    }

    func testSameNamesAreNumbered() {
        let displays = [display(1, "DELL U2720Q"), display(2, "内建显示器"), display(3, "DELL U2720Q")]
        XCTAssertEqual(DisplayModes.numbered(displays).map(\.name), ["DELL U2720Q 1", "内建显示器", "DELL U2720Q 2"])
    }

    @MainActor
    func testReadsTheDisplaysOfThisMac() throws {
        let displays = DisplayModes.all()
        let main = try XCTUnwrap(displays.first)
        XCTAssertTrue(main.isMain)
        XCTAssertFalse(main.name.isEmpty)
        let current = try XCTUnwrap(main.current)
        XCTAssertGreaterThan(current.width, 0)
        XCTAssertGreaterThanOrEqual(current.pixelWidth, current.width)
        // 正在用的大小一定在列表里，打着勾
        XCTAssertTrue(DisplayModes.choices(main.modes, current: current).contains { $0.mode.size == current.size })
    }

    /// 假的显示器：记下换了什么，可以让它换不成
    @MainActor
    private final class FakeDisplays {
        var displays: [DisplayModes.Display]
        var applied: [DisplayModes.Mode] = []
        var mainRequests: [CGDirectDisplayID] = []
        var refuses = false

        init(_ displays: [DisplayModes.Display]) {
            self.displays = displays
        }

        var backend: ResolutionModel.Backend {
            ResolutionModel.Backend(displays: { self.displays }, apply: { mode, id in
                self.applied.append(mode)
                guard !self.refuses, let index = self.displays.firstIndex(where: { $0.id == id }) else { return false }
                self.displays[index].current = mode
                return true
            }, makeMain: { id, _ in
                self.mainRequests.append(id)
                guard !self.refuses else { return false }
                for index in self.displays.indices {
                    self.displays[index].isMain = self.displays[index].id == id
                }
                return true
            })
        }
    }

    private var builtInModes: [DisplayModes.Mode] {
        [mode(1, 1512, 982, rate: 120, isDefault: true), mode(2, 1800, 1169, rate: 120)]
    }

    private var externalModes: [DisplayModes.Mode] {
        [mode(11, 1920, 1080), mode(12, 2560, 1440, isDefault: true), mode(13, 2560, 1440, rate: 30)]
    }

    @MainActor
    private func fakeDisplays() -> FakeDisplays {
        FakeDisplays([
            display(1, "内建显示器", builtIn: true, main: true, current: builtInModes[0], modes: builtInModes),
            display(2, "LG HDR 4K", current: externalModes[0], modes: externalModes),
        ])
    }

    @MainActor
    func testExternalDisplayChangesWaitForKeep() {
        let fake = fakeDisplays()
        let external = externalModes
        let model = ResolutionModel(backend: fake.backend, selecting: 2, usesTimers: false)
        XCTAssertEqual(model.selected?.id, 2)
        XCTAssertEqual(model.choices.map { DisplayModes.sizeText($0.mode) }, ["1920 × 1080", "2560 × 1440"])

        // 外接的换了：等着确认，倒计时
        model.choose(external[1])
        XCTAssertEqual(model.selected?.current, external[1])
        XCTAssertEqual(model.pending?.remaining, ResolutionModel.confirmSeconds)
        XCTAssertEqual(model.pendingText, "保留这个分辨率吗？15 秒后换回原来的")
        // 又换了刷新率：到时候还是换回最早的那个
        XCTAssertEqual(model.rates.map(\.ioID), [12, 13])
        model.choose(external[2])
        XCTAssertEqual(model.pending?.previous, external[0])
        for _ in 1..<ResolutionModel.confirmSeconds {
            model.tick()
        }
        XCTAssertEqual(model.pending?.remaining, 1)
        model.tick()
        XCTAssertNil(model.pending)
        XCTAssertEqual(fake.applied.last, external[0])
        XCTAssertEqual(model.selected?.current, external[0])

        // 点了「保留」就留着
        model.choose(external[1])
        model.keep()
        XCTAssertNil(model.pending)
        model.tick()
        XCTAssertEqual(model.selected?.current, external[1])

        // 又换回原来的那个：不用再确认
        model.choose(external[0])
        XCTAssertEqual(model.pending?.previous, external[1])
        model.choose(external[1])
        XCTAssertNil(model.pending)

        // 还在等确认时卡片关掉了：换回去
        model.choose(external[0])
        model.closed()
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.selected?.current, external[1])
        // 没在等确认时关掉什么都不做
        let count = fake.applied.count
        model.closed()
        XCTAssertEqual(fake.applied.count, count)
    }

    @MainActor
    func testBuiltInChangesApplyAtOnceAndMainDisplay() {
        let fake = fakeDisplays()
        let builtIn = builtInModes
        let external = externalModes
        let model = ResolutionModel(backend: fake.backend, usesTimers: false)
        // 没指定时选第一台
        XCTAssertEqual(model.selected?.id, 1)
        // 这个大小只有一种刷新率：不用选
        XCTAssertEqual(model.rates.count, 1)
        model.choose(builtIn[1])
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.selected?.current, builtIn[1])
        // 选现在用的那个什么都不做
        let count = fake.applied.count
        model.choose(builtIn[1])
        XCTAssertEqual(fake.applied.count, count)

        // 外接的在等确认时去换内建的：外接的留着
        model.selectedID = 2
        model.choose(external[1])
        XCTAssertNotNil(model.pending)
        model.selectedID = 1
        model.choose(builtIn[0])
        XCTAssertNil(model.pending)
        XCTAssertEqual(fake.displays[1].current, external[1])

        // 设成主显示器；已经是了就不再设
        model.selectedID = 2
        model.makeMain()
        XCTAssertEqual(fake.mainRequests, [2])
        XCTAssertEqual(model.selected?.isMain, true)
        XCTAssertNil(model.message)
        model.makeMain()
        XCTAssertEqual(fake.mainRequests, [2])

        // 换不成时说一声
        fake.refuses = true
        model.choose(external[0])
        XCTAssertEqual(model.message, "换不成 1920 × 1080（60 Hz）")
        XCTAssertNil(model.pending)
        model.selectedID = 1
        model.makeMain()
        XCTAssertEqual(model.message, "没能把「内建显示器」设成主显示器")
        fake.refuses = false

        // 在等确认的显示器拔掉了：不用换回去了，改选还在的那台
        model.selectedID = 2
        model.choose(external[0])
        XCTAssertNotNil(model.pending)
        fake.displays.removeLast()
        model.refresh()
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.selected?.id, 1)
    }

    @MainActor
    func testDemoDisplaysAndPlugin() {
        let model = ResolutionModel(backend: ResolutionPlugin.demoBackend(), selecting: ResolutionPlugin.demoStudioDisplay, usesTimers: false)
        XCTAssertEqual(model.displays.map(\.name), ["内建显示器", "Studio Display"])
        XCTAssertEqual(model.choices.map { DisplayModes.sizeText($0.mode) },
                       ["1280 × 720", "1600 × 900", "2048 × 1152", "2560 × 1440", "2880 × 1620", "5120 × 2880"])
        XCTAssertEqual(model.choices.map(\.isBlurry), [true, false, false, false, false, false])
        XCTAssertEqual(model.choices.first { $0.isDefault }?.mode.width, 2560)
        // 外接的换了要确认
        if let mode = model.choices.first(where: { $0.mode.width == 2560 })?.mode {
            model.choose(mode)
        }
        XCTAssertEqual(model.selected?.current?.width, 2560)
        XCTAssertNotNil(model.pending)
        model.keep()

        model.selectedID = ResolutionPlugin.demoBuiltIn
        XCTAssertEqual(model.choices.count, 5)
        XCTAssertEqual(model.rates.map(\.refreshRate), [120, 60, 50, 48])
        model.selectedID = ResolutionPlugin.demoStudioDisplay
        model.makeMain()
        XCTAssertEqual(model.displays.first { $0.isMain }?.id, ResolutionPlugin.demoStudioDisplay)
        XCTAssertTrue(ResolutionPlugin().info.canHandle(.empty))
    }
}
