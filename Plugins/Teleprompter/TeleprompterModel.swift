import Foundation
@testable import Pop

/// 提词器：稿子按一定速度往上滚，可以暂停、调速度、调字号、从头再来
@MainActor
final class TeleprompterModel: ObservableObject {
    /// 每秒往上滚多少点
    nonisolated static let speeds: ClosedRange<Double> = 10...150
    nonisolated static let defaultSpeed: Double = 40
    nonisolated static let speedStep: Double = 8
    nonisolated static let fontSizes: ClosedRange<Double> = 18...60
    nonisolated static let defaultFontSize: Double = 32
    nonisolated static let fontStep: Double = 4
    static let speedKey = "pop.teleprompter.speed"
    static let fontSizeKey = "pop.teleprompter.fontSize"

    @Published var text: String
    @Published private(set) var speed: Double
    @Published private(set) var fontSize: Double
    @Published private(set) var paused = false
    /// 已经往上滚了多少点
    @Published private(set) var offset: Double = 0
    /// 稿子排好以后有多高、看得见的部分有多高（界面排版后告诉模型）
    var contentHeight: Double = 0
    var viewportHeight: Double = 0

    init(text: String, speed: Double = defaultSpeed, fontSize: Double = defaultFontSize) {
        self.text = text
        self.speed = Self.clamp(speed, Self.speeds)
        self.fontSize = Self.clamp(fontSize, Self.fontSizes)
    }

    /// 最后一行滚到看得见的区域上三分之一处就停
    var maxOffset: Double {
        max(contentHeight - viewportHeight / 3, 0)
    }

    var reachedEnd: Bool {
        contentHeight > 0 && offset >= maxOffset
    }

    /// 过了 seconds 秒：没暂停就往上滚，滚到头自动停
    func advance(by seconds: Double) {
        guard !paused, seconds > 0 else { return }
        offset = min(offset + speed * seconds, maxOffset)
        if reachedEnd {
            paused = true
        }
    }

    func togglePause() {
        // 滚到头以后再按一次：从头开始
        if paused, reachedEnd {
            restart()
            return
        }
        paused.toggle()
    }

    func restart() {
        offset = 0
        paused = false
    }

    func faster() {
        speed = Self.clamp(speed + Self.speedStep, Self.speeds)
    }

    func slower() {
        speed = Self.clamp(speed - Self.speedStep, Self.speeds)
    }

    func bigger() {
        fontSize = Self.clamp(fontSize + Self.fontStep, Self.fontSizes)
    }

    func smaller() {
        fontSize = Self.clamp(fontSize - Self.fontStep, Self.fontSizes)
    }

    /// 往回、往前挪一点（滚轮、方向键 ← →）
    func scroll(by points: Double) {
        offset = Self.clamp(offset + points, 0...max(maxOffset, 0))
    }

    /// 按现在的速度从头读完要多久
    var totalDuration: TimeInterval {
        speed > 0 ? maxOffset / speed : 0
    }

    /// 速度的说法：每分钟大约滚过多少行
    nonisolated static func linesPerMinute(speed: Double, fontSize: Double) -> Int {
        let lineHeight = fontSize * 1.45
        return Int((speed * 60 / lineHeight).rounded())
    }

    nonisolated static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
