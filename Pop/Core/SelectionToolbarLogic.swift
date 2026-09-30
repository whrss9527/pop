import CoreGraphics
import Foundation

/// 选中文字后弹出的工具条：什么时候去读选区、放哪些功能、摆在哪里。
enum SelectionToolbarLogic {
    /// 拖动多远才算拖着选了一段（点）
    static let minimumDrag: CGFloat = 8
    /// 工具条上最多放几个功能
    static let maxItems = 5

    /// 鼠标抬起时要不要去看选区：拖着选了一段（移动够远、不是在拖文件），或者双击选词、三击选段。
    /// 单击不看，所以平时点来点去不会去读选区。
    static func isSelectionGesture(from down: CGPoint, to up: CGPoint, clickCount: Int, startedDragAndDrop: Bool) -> Bool {
        if clickCount == 2 || clickCount == 3 {
            return true
        }
        guard !startedDragAndDrop else { return false }
        let dx = up.x - down.x
        let dy = up.y - down.y
        return (dx * dx + dy * dy).squareRoot() >= minimumDrag
    }

    /// 工具条上的功能：按圆盘的顺序，取能处理这段文字的前几个（不需要选中内容的功能不放）
    static func items(layout: RingLayout, catalog: [PluginInfo], installed: Set<String>, content: ClassifiedContent,
                      limit: Int = maxItems) -> [PluginInfo] {
        var result: [PluginInfo] = []
        for id in layout.slots.compactMap({ $0 }) where installed.contains(id) {
            guard let info = catalog.first(where: { $0.id == id }), !info.accepts.isEmpty || info.optionalContent,
                  info.canHandle(content), !result.contains(where: { $0.id == id }) else { continue }
            result.append(info)
            if result.count >= limit {
                break
            }
        }
        return result
    }

    /// 辅助功能给的矩形是 Quartz 坐标（主屏左上角为原点，y 向下），换成 AppKit 坐标（左下角为原点，y 向上）
    static func appKitRect(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// 选区在鼠标抬起的地方附近才弹：拖的是窗口、选区还是之前那一段时不弹
    static func selection(_ bounds: CGRect, isNear pointer: CGPoint) -> Bool {
        bounds.insetBy(dx: -60, dy: -60).contains(pointer)
    }

    /// 放在选区上方正中，上面放不下就放到下面，左右不出屏幕（AppKit 坐标）。
    /// 选区很高（选了好几段）或者读不到位置时，对着鼠标抬起的地方
    static func frame(size: CGSize, selection: CGRect?, pointer: CGPoint, screen: CGRect, gap: CGFloat = 6) -> CGRect {
        let target: CGRect
        if let selection, selection.height > 0, selection.height <= 80 {
            target = selection
        } else {
            target = CGRect(x: pointer.x, y: pointer.y - 10, width: 0, height: 20)
        }
        var y = target.maxY + gap
        if y + size.height > screen.maxY {
            y = target.minY - gap - size.height
        }
        let x = min(max(target.midX - size.width / 2, screen.minX + 4), screen.maxX - size.width - 4)
        y = min(max(y, screen.minY + 4), screen.maxY - size.height - 4)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
