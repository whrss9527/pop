import CoreGraphics
import Foundation
@testable import Pop

/// 画中画能放哪些窗口，小窗放在哪、多大：纯逻辑，方便测试
enum PiPWindows {
    /// 屏幕上的一个窗口（从 ScreenCaptureKit 读到的；测试、演示时自己造）
    struct Item: Identifiable, Equatable {
        let id: CGWindowID
        let pid: pid_t
        let appName: String
        let title: String
        /// 窗口在屏幕上的位置：CG 坐标（主屏幕左上角为原点，往下是正）
        let frame: CGRect
        /// 窗口层级：普通窗口是 0，菜单栏、程序坞、浮窗在上面
        var layer = 0
        var isOnScreen = true

        /// 列表里写的名字：「Safari — 发布会直播」，没有标题时只写 App 的名字
        var displayTitle: String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != appName else { return appName }
            return "\(appName) — \(trimmed)"
        }
    }

    /// 太小的窗口不列（工具条、悬浮按钮）
    static let minimumSize = CGSize(width: 120, height: 80)

    /// 能放进小窗的窗口：普通窗口、在屏幕上、不太小、不是 Pop 自己的；按从前到后排（order 是从前到后的窗口号，不在里面的排后面）
    static func candidates(_ items: [Item], ownPID: pid_t, order: [CGWindowID]) -> [Item] {
        let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return items
            .filter { $0.layer == 0 && $0.isOnScreen && $0.pid != ownPID
                && $0.frame.width >= minimumSize.width && $0.frame.height >= minimumSize.height }
            .enumerated()
            .sorted { (rank[$0.element.id] ?? Int.max, $0.offset) < (rank[$1.element.id] ?? Int.max, $1.offset) }
            .map(\.element)
    }

    /// 指针下最前面的那个窗口（point 是 CG 坐标，items 按从前到后排）
    static func item(at point: CGPoint, in items: [Item]) -> Item? {
        items.first { $0.frame.contains(point) }
    }

    /// AppKit 的屏幕坐标（主屏幕左下角为原点，往上是正）换成 CG 坐标
    static func cgPoint(fromAppKit point: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// CG 坐标的一块区域换成 AppKit 坐标（y 轴翻转，两个方向是同一个公式）
    static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

/// 小窗的大小和位置
enum PiPLayout {
    /// 小窗长边的范围（点），默认 360
    static let longSideRange: ClosedRange<CGFloat> = 160...960
    static let defaultLongSide: CGFloat = 360
    /// 右键菜单里的「小」「中」「大」
    static let presets: [CGFloat] = [240, 360, 520]
    /// 离屏幕边缘、离别的小窗的距离
    static let margin: CGFloat = 20
    static let gap: CGFloat = 12

    /// 按原来窗口的宽高比算小窗的大小：长边是 longSide
    static func size(for windowSize: CGSize, longSide: CGFloat) -> CGSize {
        let width = max(windowSize.width, 1)
        let height = max(windowSize.height, 1)
        return width >= height
            ? CGSize(width: longSide, height: max(1, (longSide * height / width).rounded()))
            : CGSize(width: max(1, (longSide * width / height).rounded()), height: longSide)
    }

    /// 新开的小窗放在屏幕右下角；那里已经有小窗了就往上摞，摞到顶就往左挪一列；都放不下时放在右下角
    static func defaultFrame(size: CGSize, in visible: CGRect, occupied: [CGRect]) -> CGRect {
        let corner = CGRect(x: visible.maxX - margin - size.width, y: visible.minY + margin, width: size.width, height: size.height)
        var x = corner.minX
        while x >= visible.minX + margin - 0.5 {
            var frame = CGRect(x: x, y: corner.minY, width: size.width, height: size.height)
            while frame.maxY <= visible.maxY - margin + 0.5 {
                let blocking = occupied.filter { $0.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(frame) }
                if blocking.isEmpty {
                    return frame
                }
                frame.origin.y = (blocking.map(\.maxY).max() ?? frame.minY) + gap
            }
            let column = occupied.filter { $0.minX < x + size.width && $0.maxX > x }.map(\.minX).min() ?? x
            x = min(x, column) - gap - size.width
        }
        return corner
    }

    /// 换大小：中心不动，超出屏幕的挪回来。宽高比按 aspect（原来的窗口）算，不按小窗现在的大小：
    /// 小窗的大小取过整，一次次按它算会越来越歪
    static func resized(_ frame: CGRect, longSide: CGFloat, within visible: CGRect, aspect: CGSize? = nil) -> CGRect {
        let size = size(for: aspect ?? frame.size, longSide: longSide)
        var result = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        result.origin.x = min(max(result.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
        result.origin.y = min(max(result.minY, visible.minY), max(visible.minY, visible.maxY - size.height))
        return result
    }

    /// 滚动：往上滚变大、往下滚变小
    static func scrolled(_ longSide: CGFloat, by delta: CGFloat) -> CGFloat {
        min(max(longSide + delta, longSideRange.lowerBound), longSideRange.upperBound)
    }

    /// 存着的长边不在范围里时用默认的
    static func savedLongSide(_ value: Double) -> CGFloat {
        longSideRange.contains(CGFloat(value)) ? CGFloat(value) : defaultLongSide
    }

    /// 抓窗口画面用多大的像素：和小窗显示出来的一样大（按屏幕倍率），至少 64
    static func captureSize(for size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (max(64, Int((size.width * scale).rounded())), max(64, Int((size.height * scale).rounded())))
    }
}
