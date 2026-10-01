import AppKit
import UniformTypeIdentifiers

extension OverlayDemo {
    /// 文件信息演示用的照片：一张渐变的风景色块，带着相机、参数、拍摄时间和位置（放在临时文件夹里）
    static func samplePhoto() -> URL? {
        let width = 1200
        let height = 900
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: [CGColor(red: 0.36, green: 0.62, blue: 0.9, alpha: 1),
                                                 CGColor(red: 0.95, green: 0.78, blue: 0.55, alpha: 1)] as CFArray,
                                        locations: [0, 1]) else { return nil }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: CGFloat(height)), end: .zero, options: [])
        guard let image = context.makeImage() else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-demo")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "西湖.jpg")
        try? FileManager.default.removeItem(at: url)
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 16 Pro"] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "iPhone 16 Pro back triple camera 6.765mm f/1.78",
                kCGImagePropertyExifFocalLength: 6.765,
                kCGImagePropertyExifFocalLenIn35mmFilm: 24,
                kCGImagePropertyExifFNumber: 1.78,
                kCGImagePropertyExifExposureTime: 1.0 / 640,
                kCGImagePropertyExifISOSpeedRatings: [80],
                kCGImagePropertyExifDateTimeOriginal: "2026:09:27 17:42:18",
                kCGImagePropertyExifOffsetTimeOriginal: "+08:00",
            ] as [CFString: Any],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 30.2431, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 120.1470, kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSAltitude: 8.2, kCGImagePropertyGPSAltitudeRef: 0,
            ] as [CFString: Any],
        ]
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}
