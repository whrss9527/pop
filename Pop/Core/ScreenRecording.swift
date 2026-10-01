import CoreGraphics
import Foundation

/// 录屏用到的计算：选区域、换算坐标、输出尺寸、文件名和存放位置
enum ScreenRecording {
    /// 录什么声音。电脑里的声音和麦克风一次只录一种：两种一起录会存成两条音轨，有的播放器只放第一条
    enum Audio: String, CaseIterable, Identifiable {
        case off
        case system
        case microphone

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return String(localized: "不录声音")
            case .system: return String(localized: "电脑里的声音")
            case .microphone: return String(localized: "麦克风")
            }
        }
    }

    struct Options: Equatable {
        var audio = Audio.off
        /// 显示鼠标点击
        var showClicks = false
        /// 在录的区域下边显示按下的组合键
        var showKeys = false
        /// 选好区域以后先倒数 3 秒再开始录
        var countdown = false

        static let audioKey = "pop.screenRecord.audio"
        /// 0.30.0 的「录上电脑里的声音」勾选，读旧设置用
        static let systemAudioKey = "pop.screenRecord.systemAudio"
        static let showClicksKey = "pop.screenRecord.showClicks"
        static let showKeysKey = "pop.screenRecord.showKeys"
        static let countdownKey = "pop.screenRecord.countdown"

        /// 上次选的
        static func saved(in defaults: UserDefaults = .standard) -> Options {
            let audio = defaults.string(forKey: audioKey).flatMap(Audio.init(rawValue:))
                ?? (defaults.bool(forKey: systemAudioKey) ? .system : .off)
            return Options(audio: audio, showClicks: defaults.bool(forKey: showClicksKey), showKeys: defaults.bool(forKey: showKeysKey),
                           countdown: defaults.bool(forKey: countdownKey))
        }

        func save(in defaults: UserDefaults = .standard) {
            defaults.set(audio.rawValue, forKey: Self.audioKey)
            defaults.set(showClicks, forKey: Self.showClicksKey)
            defaults.set(showKeys, forKey: Self.showKeysKey)
            defaults.set(countdown, forKey: Self.countdownKey)
        }
    }

    static var microphoneHint: String {
        String(localized: "要先在「系统设置 → 隐私与安全性 → 麦克风」里允许 Pop")
    }

    /// 录好的视频
    struct Clip: Equatable {
        let url: URL
        let duration: TimeInterval
        let width: Int
        let height: Int
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    static var permissionHint: String {
        String(localized: "要先在「系统设置 → 隐私与安全性 → 录屏与系统录音」里允许 Pop，允许后重新打开 Pop")
    }

    /// 屏幕上的一个窗口（CGWindowList 给的：左上角为原点的全局坐标）
    struct WindowInfo: Equatable {
        var frame: CGRect
        var layer: Int
        var ownerPID: pid_t
        var alpha: Double
    }

    /// 输出视频最长的一边、最短的一边最多这么多像素，再大就等比缩小
    static let maxLongSide: CGFloat = 3840
    static let maxShortSide: CGFloat = 2160
    /// 拖出来的区域至少这么大（点）才算，小了当作单击
    static let minimumSide: CGFloat = 16

    /// 区域的大小（点）乘上屏幕的缩放（每点几个像素）得到视频的像素尺寸：太大时等比缩小，宽高取偶数
    static func outputSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        let width = points.width * scale
        let height = points.height * scale
        let long = max(width, height, 1)
        let short = max(min(width, height), 1)
        let factor = min(1, maxLongSide / long, maxShortSide / short)
        func even(_ value: CGFloat) -> Int {
            max(2, Int((value + 0.001).rounded(.down)) / 2 * 2)
        }
        return (even(width * factor), even(height * factor))
    }

    /// 全局坐标（左下角为原点）里的区域，换成这块屏幕里左上角为原点的坐标（录屏的 sourceRect 用这种）
    static func sourceRect(_ region: CGRect, in screenFrame: CGRect) -> CGRect {
        let local = region.intersection(screenFrame)
        guard !local.isNull else { return .zero }
        return CGRect(x: local.minX - screenFrame.minX, y: screenFrame.maxY - local.maxY, width: local.width, height: local.height)
    }

    /// 从 start 拖到 end 拉出的区域，取整到整点，不超出 bounds
    static func region(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        let minX = min(start.x, end.x).rounded(), maxX = max(start.x, end.x).rounded()
        let minY = min(start.y, end.y).rounded(), maxY = max(start.y, end.y).rounded()
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).intersection(bounds)
        return rect.isNull ? .zero : rect
    }

    /// 指针下面最上面的普通窗口（全局坐标，左下角为原点），超出屏幕的部分切掉；排除 ownPID 的窗口、透明的和很小的
    /// windows 按从前到后的顺序，primaryHeight 是主屏幕的高度（两种坐标换算用）
    static func window(at point: CGPoint, in windows: [WindowInfo], ownPID: pid_t, primaryHeight: CGFloat, screenFrame: CGRect) -> CGRect? {
        for window in windows where window.layer == 0 && window.ownerPID != ownPID && window.alpha > 0.01 {
            let frame = CGRect(x: window.frame.minX, y: primaryHeight - window.frame.maxY,
                               width: window.frame.width, height: window.frame.height)
            guard frame.width >= 40, frame.height >= 40, frame.contains(point) else { continue }
            let visible = frame.intersection(screenFrame)
            return visible.isNull || visible.width < minimumSide || visible.height < minimumSide ? nil : visible
        }
        return nil
    }

    /// 文件名：「录屏 2026-09-30 15.30.12」
    static func fileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = formatter.string(from: date)
        return String(localized: "录屏 \(stamp)")
    }

    /// 系统截屏设置的存放位置（「截屏」App 的「选项」里改的）
    static var screenshotLocation: String? {
        UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
    }

    /// 存到系统截屏存放的文件夹；没设置过或者文件夹不在了就存到桌面
    static func folder(screenshotLocation: String?) -> URL {
        if let location = screenshotLocation?.trimmingCharacters(in: .whitespaces), !location.isEmpty {
            let path = (location as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop")
    }

    /// 录了多久：「00:12」「1:02:03」
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds)) : 0
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }

    /// 录好以后的卡片：可以接着转成 GIF、截取一段
    static func card(_ clip: Clip) -> ResultCard {
        let folder = FileManager.default.displayName(atPath: clip.url.deletingLastPathComponent().path(percentEncoded: false))
        // 像素数先转成文字再插进去，不然英文界面会加上千分位
        let duration = durationText(clip.duration)
        let width = String(clip.width)
        let height = String(clip.height)
        return ResultCard(title: String(localized: "录好了"), body: clip.url.lastPathComponent,
                          detail: String(localized: "\(duration) · \(width) × \(height) · 存在「\(folder)」"),
                          buttons: [CardButton(title: VideoConverter.Operation.gif.title, action: .convertVideos([clip.url], .gif)),
                                    CardButton(title: String(localized: "截取一段…"), action: .trimMedia(clip.url)),
                                    CardButton(title: String(localized: "打开"), action: .open(clip.url)),
                                    CardButton(title: String(localized: "在访达中显示"), action: .reveal(clip.url))])
    }
}
