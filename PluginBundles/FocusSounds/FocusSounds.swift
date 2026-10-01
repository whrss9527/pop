import Foundation
@testable import Pop

/// 白噪音插件能放的声音：都在本机实时生成，不用下载音频文件
enum FocusSound: String, CaseIterable, Identifiable {
    case white, pink, brown, rain, waves

    var id: String { rawValue }

    var title: String {
        switch self {
        case .white: return String(localized: "白噪音")
        case .pink: return String(localized: "粉红噪音")
        case .brown: return String(localized: "棕色噪音")
        case .rain: return String(localized: "雨声")
        case .waves: return String(localized: "海浪")
        }
    }

    /// 一句话说是什么声音
    var detail: String {
        switch self {
        case .white: return String(localized: "各个频率一样响，最能盖住说话声和键盘声")
        case .pink: return String(localized: "低音多一些，比白噪音柔和")
        case .brown: return String(localized: "低沉，像远处的瀑布、飞机舱里")
        case .rain: return String(localized: "细密的雨点打在窗上")
        case .waves: return String(localized: "海浪一阵一阵地涌上来又退下去")
        }
    }

    var symbol: String {
        switch self {
        case .white: return "waveform"
        case .pink: return "waveform.path"
        case .brown: return "waveform.path.ecg"
        case .rain: return "cloud.rain"
        case .waves: return "water.waves"
        }
    }

    /// 实时线程里用序号传：不用 allCases（那会新建数组）
    var index: Int {
        switch self {
        case .white: return 0
        case .pink: return 1
        case .brown: return 2
        case .rain: return 3
        case .waves: return 4
        }
    }

    init(index: Int) {
        switch index {
        case 1: self = .pink
        case 2: self = .brown
        case 3: self = .rain
        case 4: self = .waves
        default: self = .white
        }
    }
}

/// 生成一路声音，每次一个样本（-1…1）。实时线程里调用：不分配内存、不加锁
struct NoiseGenerator {
    let sound: FocusSound
    let sampleRate: Float
    private var state: UInt64
    // 粉红噪音（Paul Kellet 的滤波）
    private var b0: Float = 0
    private var b1: Float = 0
    private var b2: Float = 0
    private var b3: Float = 0
    private var b4: Float = 0
    private var b5: Float = 0
    private var b6: Float = 0
    // 棕色噪音：白噪音一点点累加
    private var brown: Float = 0
    // 雨声：去掉低音的粉红噪音是远处的雨；雨点是一小段很快衰减的、偏高频的噪音
    private var low: Float = 0
    private var drop: Float = 0
    private var smooth: Float = 0
    // 海浪：很慢的起伏
    private var phase: Float = 0
    private var swellRate: Float

    init(sound: FocusSound, sampleRate: Double = 44_100, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        self.sound = sound
        self.sampleRate = Float(sampleRate)
        state = seed == 0 ? 1 : seed
        // 一个浪 9～13 秒，左右两路的种子不同，节奏也就错开一点
        swellRate = 1 / (9 + Float(seed % 5))
        phase = Float(seed % 97) / 97
    }

    mutating func next() -> Float {
        let value: Float
        switch sound {
        case .white:
            value = white() * 0.45
        case .pink:
            value = pink()
        case .brown:
            value = brownian()
        case .rain:
            value = rain()
        case .waves:
            value = waves()
        }
        return min(max(value, -1), 1)
    }

    /// -1…1 的均匀随机数（xorshift64*）
    mutating func white() -> Float {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let mixed = state &* 2_685_821_657_736_338_717
        return Float(mixed >> 40) / 8_388_608 - 1
    }

    /// 0…1 的均匀随机数
    private mutating func unit() -> Float {
        (white() + 1) / 2
    }

    private mutating func pink() -> Float {
        let noise = white()
        b0 = 0.99886 * b0 + noise * 0.0555179
        b1 = 0.99332 * b1 + noise * 0.0750759
        b2 = 0.969 * b2 + noise * 0.153852
        b3 = 0.8665 * b3 + noise * 0.3104856
        b4 = 0.55 * b4 + noise * 0.5329522
        b5 = -0.7616 * b5 - noise * 0.016898
        let sum = b0 + b1 + b2 + b3 + b4 + b5 + b6 + noise * 0.5362
        b6 = noise * 0.115926
        return sum * 0.11
    }

    private mutating func brownian() -> Float {
        brown = (brown + 0.02 * white()) / 1.02
        return brown * 3.5
    }

    private mutating func rain() -> Float {
        // 远处的雨：粉红噪音减掉 400 Hz 以下的部分
        let noise = pink()
        low += (noise - low) * 0.055
        let bed = (noise - low) * 1.4
        // 近处的雨点：每秒三十来个，可以叠在一起，每个几毫秒就衰减下去
        if unit() < 30 / sampleRate {
            drop = min(drop + 0.2 + 0.6 * unit(), 1)
        }
        drop *= 0.9965
        let hiss = white()
        smooth += (hiss - smooth) * 0.35
        return bed + (hiss - smooth) * drop * 0.45
    }

    private mutating func waves() -> Float {
        phase += swellRate / sampleRate
        if phase >= 1 {
            phase -= 1
        }
        // 0…1 的起伏，平方以后浪头更明显；浪头上带一点浪花的沙沙声
        let swell = 0.5 - 0.5 * cos(2 * Float.pi * phase)
        let crest = swell * swell
        let body = brownian() * (0.25 + 0.75 * crest)
        let foam = pink() * 0.45 * crest * crest
        return (body + foam) * 1.1
    }
}
