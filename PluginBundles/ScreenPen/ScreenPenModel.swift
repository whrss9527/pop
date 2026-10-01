import AppKit
import SwiftUI
@testable import Pop

/// 屏幕画笔的工具：画笔、荧光笔、箭头、方框、椭圆
enum ScreenPenTool: String, CaseIterable, Identifiable {
    case pen, highlighter, arrow, rectangle, ellipse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pen: return String(localized: "画笔")
        case .highlighter: return String(localized: "荧光笔")
        case .arrow: return String(localized: "箭头")
        case .rectangle: return String(localized: "方框")
        case .ellipse: return String(localized: "椭圆")
        }
    }

    var symbol: String {
        switch self {
        case .pen: return "scribble"
        case .highlighter: return "highlighter"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        }
    }

    /// 快捷键：P 画笔、H 荧光笔、A 箭头、R 方框、O 椭圆（和截图标注一样）
    var key: Character {
        switch self {
        case .pen: return "p"
        case .highlighter: return "h"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        }
    }

    var kind: Annotation.Kind {
        switch self {
        case .pen, .highlighter: return .pen
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        }
    }

    var lineWidth: CGFloat { self == .highlighter ? 22 : 5 }

    /// 荧光笔是半透明的，盖在字上还看得清
    var opacity: CGFloat { self == .highlighter ? 0.4 : 1 }
}

/// 屏幕上的一笔
struct ScreenPenStroke: Identifiable, Equatable {
    var annotation: Annotation
    var tool: ScreenPenTool
    /// 画完的时间（自动消失从这时开始算）
    var finishedAt: TimeInterval?

    var id: UUID { annotation.id }
}

/// 屏幕画笔画了些什么、现在用什么笔。坐标是屏幕上的点，左上角为原点
@MainActor
final class ScreenPenModel: ObservableObject {
    /// 自动消失时，画完多久开始淡出、淡出要多久
    nonisolated static let fadeDelay: TimeInterval = 2.5
    nonisolated static let fadeDuration: TimeInterval = 0.6
    /// 工具栏上的颜色，数字键 1～5 依次选
    static let colors: [AnnotationColor] = [.red, .yellow, .green, .blue, .white]

    @Published var tool: ScreenPenTool = .pen
    @Published var color: AnnotationColor = .red
    @Published private(set) var strokes: [ScreenPenStroke] = []
    @Published private(set) var current: ScreenPenStroke?
    /// 画完的笔迹几秒后自动消失
    @Published private(set) var fades = false
    /// 鼠标穿过画布去操作下面的窗口，画好的留在屏幕上
    @Published var passThrough = false

    /// 画好的加上正在画的那一笔
    var visibleStrokes: [ScreenPenStroke] {
        strokes + (current.map { [$0] } ?? [])
    }

    func begin(at point: CGPoint) {
        current = ScreenPenStroke(annotation: Annotation(kind: tool.kind, points: [point], color: color, lineWidth: tool.lineWidth), tool: tool)
    }

    /// 拖到 point；constrained（按住 ⇧）时画笔和荧光笔画直线，方框、椭圆画成正的，箭头转到 45° 的整数倍
    func drag(to point: CGPoint, constrained: Bool = false) {
        guard var stroke = current else { return }
        let start = stroke.annotation.start
        switch stroke.annotation.kind {
        case .pen where constrained:
            stroke.annotation.points = [start, point]
        case .pen:
            // 挨得太近的点不要，线条更顺
            if let last = stroke.annotation.points.last, hypot(point.x - last.x, point.y - last.y) < 1.5 { return }
            stroke.annotation.points.append(point)
        default:
            stroke.annotation.points = [start, constrained ? Self.constrain(point, from: start, kind: stroke.annotation.kind) : point]
        }
        current = stroke
    }

    func end(at time: TimeInterval) {
        guard var stroke = current else { return }
        current = nil
        guard stroke.annotation.isMeaningful else { return }
        stroke.finishedAt = time
        strokes.append(stroke)
    }

    /// 用 tool 和 color 依次经过这些点画一笔
    func draw(_ tool: ScreenPenTool, color: AnnotationColor, through points: [CGPoint], at time: TimeInterval) {
        guard let first = points.first else { return }
        self.tool = tool
        self.color = color
        begin(at: first)
        for point in points.dropFirst() {
            drag(to: point)
        }
        end(at: time)
    }

    func undo() {
        if current != nil {
            current = nil
        } else if !strokes.isEmpty {
            strokes.removeLast()
        }
    }

    func clear() {
        strokes = []
        current = nil
    }

    /// 全部清掉，工具和颜色回到默认
    func reset() {
        clear()
        tool = .pen
        color = .red
        fades = false
        passThrough = false
    }

    /// 打开自动消失时，已经画好的从现在开始算，不会一下子全没了
    func setFades(_ on: Bool, now: TimeInterval) {
        fades = on
        if on {
            for index in strokes.indices {
                strokes[index].finishedAt = now
            }
        }
    }

    /// 去掉已经完全淡出的笔迹
    func removeFaded(now: TimeInterval) {
        guard fades, strokes.contains(where: { Self.fade(finishedAt: $0.finishedAt, now: now) <= 0 }) else { return }
        strokes.removeAll { Self.fade(finishedAt: $0.finishedAt, now: now) <= 0 }
    }

    /// 自动消失时这一笔现在的不透明度：画完 fadeDelay 秒后，在 fadeDuration 秒里淡出
    nonisolated static func fade(finishedAt: TimeInterval?, now: TimeInterval) -> CGFloat {
        guard let finishedAt else { return 1 }
        let elapsed = now - finishedAt - fadeDelay
        if elapsed <= 0 { return 1 }
        return max(0, 1 - CGFloat(elapsed / fadeDuration))
    }

    /// 按住 ⇧ 时的终点：方框、椭圆取长的一边画成正的，箭头转到最近的 45° 方向
    nonisolated static func constrain(_ point: CGPoint, from start: CGPoint, kind: Annotation.Kind) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        switch kind {
        case .rectangle, .ellipse, .mosaic:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        case .arrow:
            let length = hypot(dx, dy)
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        default:
            return point
        }
    }
}
