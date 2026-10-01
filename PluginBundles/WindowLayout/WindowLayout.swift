import CoreGraphics
@testable import Pop

/// 窗口布局：把窗口放到屏幕可用区域的某一块。坐标都是 AppKit 屏幕坐标（y 向上）。纯逻辑，方便测试。
enum WindowLayout: String, CaseIterable, Identifiable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case leftThird
    case centerThird
    case rightThird
    case maximize
    case center
    case nextDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: return String(localized: "左半屏")
        case .rightHalf: return String(localized: "右半屏")
        case .topHalf: return String(localized: "上半屏")
        case .bottomHalf: return String(localized: "下半屏")
        case .leftThird: return String(localized: "左三分之一")
        case .centerThird: return String(localized: "中间三分之一")
        case .rightThird: return String(localized: "右三分之一")
        case .maximize: return String(localized: "最大化")
        case .center: return String(localized: "居中")
        case .nextDisplay: return String(localized: "下一个显示器")
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .leftThird: return "rectangle.leadingthird.inset.filled"
        case .centerThird: return "rectangle.split.3x1"
        case .rightThird: return "rectangle.trailingthird.inset.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .center: return "rectangle.center.inset.filled"
        case .nextDisplay: return "display.2"
        }
    }

    /// 窗口在可用区域 visible 里的新位置。居中保持窗口大小（放不下时缩小到放得下）；
    /// 「下一个显示器」要知道目标屏幕，见 moved(_:from:to:)，这里原样返回。
    func frame(for window: CGRect, in visible: CGRect) -> CGRect {
        let v = visible
        let halfWidth = (v.width / 2).rounded()
        let halfHeight = (v.height / 2).rounded()
        let third = (v.width / 3).rounded()
        switch self {
        case .leftHalf:
            return CGRect(x: v.minX, y: v.minY, width: halfWidth, height: v.height)
        case .rightHalf:
            return CGRect(x: v.maxX - halfWidth, y: v.minY, width: halfWidth, height: v.height)
        case .topHalf:
            return CGRect(x: v.minX, y: v.maxY - halfHeight, width: v.width, height: halfHeight)
        case .bottomHalf:
            return CGRect(x: v.minX, y: v.minY, width: v.width, height: halfHeight)
        case .leftThird:
            return CGRect(x: v.minX, y: v.minY, width: third, height: v.height)
        case .centerThird:
            return CGRect(x: (v.midX - third / 2).rounded(), y: v.minY, width: third, height: v.height)
        case .rightThird:
            return CGRect(x: v.maxX - third, y: v.minY, width: third, height: v.height)
        case .maximize:
            return v
        case .center:
            let size = CGSize(width: min(window.width, v.width), height: min(window.height, v.height))
            return CGRect(x: (v.midX - size.width / 2).rounded(), y: (v.midY - size.height / 2).rounded(),
                          width: size.width, height: size.height)
        case .nextDisplay:
            return window
        }
    }

    /// 把窗口从一块屏幕挪到另一块：保持在屏幕上的相对位置，大小放不下时缩小。
    static func moved(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return window }
        let size = CGSize(width: min(window.width, target.width), height: min(window.height, target.height))
        let relativeX = (window.minX - source.minX) / source.width
        let relativeY = (window.minY - source.minY) / source.height
        let moved = CGRect(x: (target.minX + relativeX * target.width).rounded(),
                           y: (target.minY + relativeY * target.height).rounded(),
                           width: size.width, height: size.height)
        return ScreenGeometry.clamp(moved, within: target)
    }

    /// 窗口主要落在哪块屏幕上（重叠面积最大的那块）；和哪块都不重叠时返回 nil。
    static func screenIndex(for window: CGRect, among screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(window)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) {
                best = (index, area)
            }
        }
        return best?.index
    }
}
