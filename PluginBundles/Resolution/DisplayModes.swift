import AppKit
import CoreGraphics
@testable import Pop

/// 显示器的分辨率：每台显示器能用的显示模式，按「看起来像」多大分好；换模式，设成主显示器。
/// 都用 CoreGraphics 的公开接口，模式列表和「系统设置 → 显示器」里「显示所有分辨率」的一样。
enum DisplayModes {
    /// 一种显示模式：看起来像多大（点）、实际画多少像素、刷新率
    struct Mode: Hashable {
        /// IOKit 给的模式编号；换模式时和大小、刷新率一起用来找回系统的模式
        let ioID: Int32
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
        /// 每秒多少帧；有的内建显示器读出来是 0
        let refreshRate: Double
        /// 系统默认用的大小
        let isDefault: Bool

        /// 像素比点多（HiDPI）：文字清楚
        var isHiDPI: Bool { pixelWidth > width }
        var size: Size { Size(width: width, height: height) }

        /// 是不是同一种模式（默认标记这类不算）
        func same(as other: Mode) -> Bool {
            ioID == other.ioID && size == other.size && pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight
                && abs(refreshRate - other.refreshRate) < 0.01
        }
    }

    struct Size: Hashable, Comparable {
        let width: Int
        let height: Int

        static func < (a: Size, b: Size) -> Bool {
            (a.width, a.height) < (b.width, b.height)
        }
    }

    struct Display: Identifiable, Equatable {
        let id: CGDirectDisplayID
        var name: String
        let isBuiltIn: Bool
        var isMain: Bool
        /// 在全局坐标里的位置（主显示器左上角是原点，y 向下）
        var bounds: CGRect
        var current: Mode?
        let modes: [Mode]
    }

    /// 列表里的一行：一种「看起来像」的大小，和换过去时用的模式
    struct Choice: Identifiable, Equatable {
        let mode: Mode
        /// 系统默认的大小
        let isDefault: Bool
        /// 这台显示器能清楚显示（有 HiDPI 模式），这个大小却只有低分辨率的：文字会发虚
        let isBlurry: Bool

        var id: Size { mode.size }
    }

    /// 按「看起来像」的大小分组，从小到大（字大的在前，地方大的在后）；每组挑一个模式
    static func choices(_ modes: [Mode], current: Mode?) -> [Choice] {
        // 正在用的模式不在列表里（不该发生）也要列出来，好打勾
        var modes = modes
        if let current, !modes.contains(where: { $0.same(as: current) }) {
            modes.append(current)
        }
        let hasHiDPI = modes.contains(where: \.isHiDPI)
        // 屏幕本身有多少像素：一个点一个像素的模式里最大的那个（HiDPI 的「更多空间」会画得比屏幕还大再缩小，不算）
        let native = modes.filter { !$0.isHiDPI }.map { $0.pixelWidth * $0.pixelHeight }.max() ?? 0
        let groups = Dictionary(grouping: modes, by: \.size)
        return groups.keys.sorted().compactMap { size in
            guard let group = groups[size], let mode = best(group, current: current) else { return nil }
            // 比屏幕的像素少、又没有 HiDPI 的大小要放大着显示，文字发虚；原生分辨率不算
            let blurry = hasHiDPI && !mode.isHiDPI && mode.pixelWidth * mode.pixelHeight < native
            return Choice(mode: mode, isDefault: group.contains(where: \.isDefault), isBlurry: blurry)
        }
    }

    /// 同一个大小里挑一个：正在用的就是它；不然 HiDPI 的优先，再挑刷新率和现在一样的、最高的
    static func best(_ group: [Mode], current: Mode?) -> Mode? {
        if let current, group.contains(where: { $0.same(as: current) }) {
            return current
        }
        return group.max { rank($0, current: current) < rank($1, current: current) }
    }

    private static func rank(_ mode: Mode, current: Mode?) -> (Int, Int, Double, Int) {
        let sameRate = current.map { abs($0.refreshRate - mode.refreshRate) < 0.5 } ?? false
        return (mode.isHiDPI ? 1 : 0, sameRate ? 1 : 0, mode.refreshRate, mode.isDefault ? 1 : 0)
    }

    /// 现在这个大小能换的刷新率（一样清楚的模式），从高到低；读不出刷新率的不算
    static func rates(_ modes: [Mode], current: Mode?) -> [Mode] {
        guard let current, current.refreshRate > 0 else { return [] }
        var rates = [current]
        for mode in modes where mode.size == current.size && mode.pixelWidth == current.pixelWidth && mode.refreshRate > 0 {
            if !rates.contains(where: { abs($0.refreshRate - mode.refreshRate) < 0.01 }) {
                rates.append(mode)
            }
        }
        return rates.sorted { $0.refreshRate > $1.refreshRate }
    }

    /// 把 target 设成主显示器时每台显示器的新位置：target 挪到原点，其他的跟着平移，相互的位置不变
    static func origins(makingMain target: CGDirectDisplayID, bounds: [CGDirectDisplayID: CGRect]) -> [CGDirectDisplayID: CGPoint]? {
        guard let origin = bounds[target]?.origin else { return nil }
        return bounds.mapValues { CGPoint(x: $0.minX - origin.x, y: $0.minY - origin.y) }
    }

    /// 两台一样的显示器名字也一样：后面加上 1、2
    static func numbered(_ displays: [Display]) -> [Display] {
        let totals = Dictionary(grouping: displays, by: \.name).mapValues(\.count)
        var seen: [String: Int] = [:]
        return displays.map { display in
            guard totals[display.name, default: 0] > 1 else { return display }
            seen[display.name, default: 0] += 1
            var numbered = display
            numbered.name = "\(display.name) \(seen[display.name] ?? 1)"
            return numbered
        }
    }

    // MARK: - 写法

    /// 「1512 × 982」
    static func sizeText(_ mode: Mode) -> String {
        "\(mode.width) × \(mode.height)"
    }

    /// 「120 Hz」「59.94 Hz」
    static func rateText(_ rate: Double) -> String {
        let rounded = rate.rounded()
        if abs(rate - rounded) < 0.01 {
            return "\(Int(rounded)) Hz"
        }
        return String(format: "%.2f Hz", rate)
    }

    // MARK: - 读

    /// 这台 Mac 上正在用的显示器：主显示器在前，其他的从左到右；镜像出去的那几台不单列
    @MainActor
    static func all() -> [Display] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let names = screenNames()
        let main = CGMainDisplayID()
        // 镜像别的显示器的，CGDisplayMirrorsDisplay 返回被镜像的那台；不镜像时是 0
        let displays = ids.prefix(Int(count)).filter { CGDisplayMirrorsDisplay($0) == 0 }.map { id in
            let builtIn = CGDisplayIsBuiltin(id) != 0
            return Display(id: id, name: builtIn ? String(localized: "内建显示器") : names[id] ?? String(localized: "显示器"),
                           isBuiltIn: builtIn, isMain: id == main, bounds: CGDisplayBounds(id),
                           current: CGDisplayCopyDisplayMode(id).map(mode), modes: systemModes(of: id).map(mode))
        }
        return numbered(displays.sorted { ($0.isMain ? 0 : 1, $0.bounds.minX) < ($1.isMain ? 0 : 1, $1.bounds.minX) })
    }

    /// 指针所在的显示器（打开卡片时先选它）
    @MainActor
    static func displayUnderPointer() -> CGDirectDisplayID? {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    @MainActor
    private static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }

    /// IOKit 的模式标记里「系统默认」的那一位（IOGraphicsTypes.h 的 kDisplayModeDefaultFlag）
    private static let defaultFlag: UInt32 = 0x0000_0004

    private static func mode(_ mode: CGDisplayMode) -> Mode {
        Mode(ioID: mode.ioDisplayModeID, width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
             refreshRate: mode.refreshRate, isDefault: mode.ioFlags & defaultFlag != 0)
    }

    /// 系统列出来、能当桌面用的模式（HiDPI 和同样大小的低分辨率模式都要）
    private static func systemModes(of id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
        return modes.filter { $0.isUsableForDesktopGUI() }
    }

    // MARK: - 改

    /// 换成这个模式，一直有效（和在系统设置里换的一样）；成功时为 true
    @discardableResult
    static func apply(_ target: Mode, to display: CGDirectDisplayID) -> Bool {
        guard let mode = systemModes(of: display).first(where: { Self.mode($0).same(as: target) }) else { return false }
        return configure { config in
            CGConfigureDisplayWithDisplayMode(config, display, mode, nil) == .success
        }
    }

    /// 设成主显示器：菜单栏和程序坞挪到它上面
    @discardableResult
    static func makeMain(_ display: CGDirectDisplayID, among displays: [Display]) -> Bool {
        let bounds = Dictionary(displays.map { ($0.id, $0.bounds) }, uniquingKeysWith: { first, _ in first })
        guard let origins = origins(makingMain: display, bounds: bounds) else { return false }
        return configure { config in
            origins.allSatisfy { id, origin in
                CGConfigureDisplayOrigin(config, id, Int32(origin.x.rounded()), Int32(origin.y.rounded())) == .success
            }
        }
    }

    /// 开一次显示器设置，change 返回 false 时取消
    private static func configure(_ change: (CGDisplayConfigRef) -> Bool) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { return false }
        guard change(config) else {
            _ = CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
