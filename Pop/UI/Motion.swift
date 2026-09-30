import SwiftUI

/// 浮窗动画的参数都放在这里，调手感只改这一处。
///
/// 环境变量 POP_ANIMATION_SCALE 可以把所有动画放慢若干倍（CI 截图时用来拍动画的中间帧）。
/// 系统打开了「减弱动态效果」时，各个视图自己去掉缩放、飞出这些位移，只留淡入淡出。
enum Motion {
    static let timeScale: Double = {
        guard let text = ProcessInfo.processInfo.environment["POP_ANIMATION_SCALE"],
              let value = Double(text), value > 0 else { return 1 }
        return min(value, 40)
    }()

    /// 演示模式（CI 截图）忽略系统的「减弱动态效果」，才能拍到完整的动画
    static let ignoresReduceMotion = ProcessInfo.processInfo.environment["POP_DEMO"] == "1"

    static func seconds(_ value: Double) -> Double {
        value * timeScale
    }

    /// 圆盘展开：从中心往外展开。不回弹（临界阻尼）：回弹会让圆盘和格子冲过头再往回缩，看起来像从外往里收
    static var ringOpen: Animation {
        .spring(response: seconds(0.32), dampingFraction: 1)
    }

    /// 格子从圆心依次飞出的间隔
    static var slotStagger: Double {
        seconds(0.02)
    }

    /// 高亮在格子之间滑动、图标放大
    static var hover: Animation {
        .spring(response: seconds(0.24), dampingFraction: 0.8)
    }

    /// 选中那一格时的「按下」
    static var commit: Animation {
        .spring(response: seconds(0.22), dampingFraction: 0.55)
    }

    /// 结果卡片、列表弹出
    static var cardOpen: Animation {
        .spring(response: seconds(0.34), dampingFraction: 0.8)
    }

    /// 提示弹出
    static var toastOpen: Animation {
        .spring(response: seconds(0.3), dampingFraction: 0.7)
    }

    /// 收起：圆盘、卡片、提示都用它，收起动画结束后浮窗才真正关掉
    static var exitDuration: Double {
        seconds(0.17)
    }

    static var exit: Animation {
        .easeIn(duration: exitDuration)
    }

    /// 卡片里的内容变化（翻译结果出来、读取完成等）
    static var content: Animation {
        .easeOut(duration: seconds(0.22))
    }

    /// 列表里的选中高亮滑动
    static var selection: Animation {
        .spring(response: seconds(0.22), dampingFraction: 0.86)
    }

    /// 提示停留多久
    static var toastDuration: Double {
        seconds(1.1)
    }
}
