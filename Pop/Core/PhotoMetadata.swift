import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 照片的拍摄信息（EXIF、GPS）：相机、镜头、光圈快门、拍摄时间和拍摄地点
struct PhotoMetadata: Equatable {
    var camera: String?
    var lens: String?
    /// 6.8 mm（等效 24 mm） · f/1.8 · 1/120 秒 · ISO 64
    var exposure: String?
    var taken: String?
    var latitude: Double?
    var longitude: Double?
    /// 海拔（米），在海平面以下是负数
    var altitude: Double?

    var hasLocation: Bool { latitude != nil && longitude != nil }
    var isEmpty: Bool { camera == nil && lens == nil && exposure == nil && taken == nil && !hasLocation }

    static func read(_ url: URL) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return PhotoMetadata(properties: properties)
    }

    init(properties: [CFString: Any]) {
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        camera = Self.cameraName(make: tiff[kCGImagePropertyTIFFMake] as? String, model: tiff[kCGImagePropertyTIFFModel] as? String)
        lens = Self.nonEmpty(exif[kCGImagePropertyExifLensModel] as? String)

        var settings: [String] = []
        if let focal = Self.focalLength(Self.number(exif[kCGImagePropertyExifFocalLength]),
                                        equivalent: Self.number(exif[kCGImagePropertyExifFocalLenIn35mmFilm])) {
            settings.append(focal)
        }
        if let number = Self.number(exif[kCGImagePropertyExifFNumber]), number > 0 {
            settings.append("f/" + Self.trimmed(number))
        }
        if let seconds = Self.number(exif[kCGImagePropertyExifExposureTime]), seconds > 0 {
            settings.append(Self.shutter(seconds))
        }
        if let iso = Self.number((exif[kCGImagePropertyExifISOSpeedRatings] as? [Any])?.first), iso > 0 {
            settings.append("ISO \(Int(iso))")
        }
        exposure = settings.isEmpty ? nil : settings.joined(separator: " · ")

        let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String ?? tiff[kCGImagePropertyTIFFDateTime] as? String
        taken = original.flatMap { Self.captureDate($0, offset: exif[kCGImagePropertyExifOffsetTimeOriginal] as? String) }

        if let latitude = Self.number(gps[kCGImagePropertyGPSLatitude]), let longitude = Self.number(gps[kCGImagePropertyGPSLongitude]) {
            self.latitude = (gps[kCGImagePropertyGPSLatitudeRef] as? String)?.uppercased() == "S" ? -latitude : latitude
            self.longitude = (gps[kCGImagePropertyGPSLongitudeRef] as? String)?.uppercased() == "W" ? -longitude : longitude
            if let altitude = Self.number(gps[kCGImagePropertyGPSAltitude]) {
                self.altitude = Self.number(gps[kCGImagePropertyGPSAltitudeRef]) == 1 ? -altitude : altitude
            }
        }
    }

    /// 照片的拍摄时间：照片里记的是拍摄地的钟点，按 UTC 读进来，再按 UTC 写出来就是原来的钟点
    static func captureDate(of url: URL) -> Date? {
        guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return parser.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))))
    }

    /// 结果卡片里的几行
    var rows: [ResultCard.Row] {
        var rows: [ResultCard.Row] = []
        if let camera { rows.append(ResultCard.Row(label: "相机", value: camera)) }
        if let lens { rows.append(ResultCard.Row(label: "镜头", value: lens)) }
        if let exposure { rows.append(ResultCard.Row(label: "拍摄参数", value: exposure)) }
        if let taken { rows.append(ResultCard.Row(label: "拍摄时间", value: taken)) }
        if let latitude, let longitude {
            rows.append(ResultCard.Row(label: "拍摄地点", value: Self.coordinates(latitude: latitude, longitude: longitude)))
            if let altitude {
                rows.append(ResultCard.Row(label: "海拔", value: "\(Int(altitude.rounded())) 米"))
            }
        }
        return rows
    }

    /// 在「地图」里打开拍摄地点
    var mapURL: URL? {
        guard let latitude, let longitude else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", latitude, longitude)),
            URLQueryItem(name: "q", value: "照片拍摄地点"),
        ]
        return components?.url
    }

    // MARK: - 写法

    /// 相机名：型号里已经带了品牌就不重复（Canon + Canon EOS R5 → Canon EOS R5）
    static func cameraName(make: String?, model: String?) -> String? {
        let make = nonEmpty(make)
        guard let model = nonEmpty(model) else { return make }
        guard let make else { return model }
        let brand = make.split(separator: " ").first.map(String.init) ?? make
        if model.lowercased().hasPrefix(brand.lowercased()) {
            return model
        }
        return "\(make) \(model)"
    }

    /// 6.765 mm、等效 24 mm → 6.8 mm（等效 24 mm）
    static func focalLength(_ actual: Double?, equivalent: Double?) -> String? {
        let actual = actual.flatMap { $0 > 0 ? $0 : nil }
        let equivalent = equivalent.flatMap { $0 > 0 ? $0 : nil }
        switch (actual, equivalent) {
        case let (actual?, equivalent?):
            let actualText = trimmed(actual)
            let equivalentText = trimmed(equivalent, digits: 0)
            return actualText == equivalentText ? "\(actualText) mm" : "\(actualText) mm（等效 \(equivalentText) mm）"
        case let (actual?, nil):
            return "\(trimmed(actual)) mm"
        case let (nil, equivalent?):
            return "等效 \(trimmed(equivalent, digits: 0)) mm"
        case (nil, nil):
            return nil
        }
    }

    /// 快门：不到一秒写成 1/120 秒
    static func shutter(_ seconds: Double) -> String {
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded())) 秒"
        }
        return "\(trimmed(seconds)) 秒"
    }

    /// 北纬 31.23040°，东经 121.47370°
    static func coordinates(latitude: Double, longitude: Double) -> String {
        let north = String(format: "%.5f°", abs(latitude))
        let east = String(format: "%.5f°", abs(longitude))
        return "\(latitude < 0 ? "南纬" : "北纬") \(north)，\(longitude < 0 ? "西经" : "东经") \(east)"
    }

    /// EXIF 的时间「2026:09:29 12:30:05」写成「2026-09-29 12:30:05」，有时区就接在后面
    static func captureDate(_ raw: String, offset: String?) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        guard !text.isEmpty else { return nil }
        guard let date = parser.date(from: text) else { return text }
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let formatted = parser.string(from: date)
        guard let offset = nonEmpty(offset) else { return formatted }
        return "\(formatted)（UTC\(offset)）"
    }

    /// 最多保留一位小数，整数不带小数点
    static func trimmed(_ value: Double, digits: Int = 1) -> String {
        let factor = pow(10, Double(digits))
        let rounded = (value * factor).rounded() / factor
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.\(digits)f", rounded)
    }

    /// 系统读出来的数都是 NSNumber，不管原来是整数还是小数都能取
    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0"))),
              !text.isEmpty else { return nil }
        return text
    }
}
