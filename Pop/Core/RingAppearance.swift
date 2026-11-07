import Foundation

/// 只改变圆盘入口的外形，不改变动作编号或选择方向。
enum RingButtonShape: String, Codable, CaseIterable, Identifiable {
    case roundedRectangle
    case circle
    case square

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let value = try? decoder.singleValueContainer().decode(String.self)
        self = value.flatMap(Self.init(rawValue:)) ?? .roundedRectangle
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct RingAppearance: Codable, Equatable {
    static let scaleRange: ClosedRange<Double> = 0.8...1.6
    static let `default` = RingAppearance()

    var shape: RingButtonShape
    var scale: Double

    init(shape: RingButtonShape = .roundedRectangle, scale: Double = 1) {
        self.shape = shape
        self.scale = Self.normalize(scale)
    }

    var normalizedScale: Double { Self.normalize(scale) }
    var normalized: RingAppearance { RingAppearance(shape: shape, scale: normalizedScale) }

    private static func normalize(_ value: Double) -> Double {
        value.isFinite ? min(max(value, scaleRange.lowerBound), scaleRange.upperBound) : 1
    }

    private enum CodingKeys: String, CodingKey { case shape, scale }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = .default
            return
        }
        let shape = (try? container.decodeIfPresent(RingButtonShape.self, forKey: .shape)) ?? .roundedRectangle
        let scale = (try? container.decodeIfPresent(Double.self, forKey: .scale)) ?? 1
        self.init(shape: shape, scale: scale)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(shape, forKey: .shape)
        // 外部可直接修改 scale；持久化时也归一化，避免非有限值使整份设置无法保存。
        try container.encode(normalizedScale, forKey: .scale)
    }
}
