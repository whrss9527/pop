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

    /// 识别表格演示用的图片：一张三列四行、带格子线的版本表，像素按屏幕倍率
    static func sampleTableImage() -> CGImage? {
        let rows = [["版本", "日期", "新功能"],
                    ["0.11.0", "9月29日", "转成 Markdown"],
                    ["0.12.0", "9月29日", "正则测试"],
                    ["0.13.0", "9月29日", "加到提醒事项"]]
        let columnWidths: [CGFloat] = [110, 110, 180]
        let rowHeight: CGFloat = 40
        let size = CGSize(width: columnWidths.reduce(0, +) + 40, height: rowHeight * CGFloat(rows.count) + 40)
        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // 换成「点、左上角为原点」的坐标
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let origin = CGPoint(x: 20, y: 20)
        let tableWidth = columnWidths.reduce(0, +)
        // 表头底色
        context.setFillColor(NSColor(srgbRed: 0.93, green: 0.94, blue: 0.97, alpha: 1).cgColor)
        context.fill(CGRect(x: origin.x, y: origin.y, width: tableWidth, height: rowHeight))
        context.setStrokeColor(NSColor(srgbRed: 0.6, green: 0.62, blue: 0.68, alpha: 1).cgColor)
        context.setLineWidth(1)
        for index in 0...rows.count {
            let y = origin.y + CGFloat(index) * rowHeight
            context.move(to: CGPoint(x: origin.x, y: y))
            context.addLine(to: CGPoint(x: origin.x + tableWidth, y: y))
        }
        var x = origin.x
        for width in [0] + columnWidths.map({ Int($0) }) {
            x += CGFloat(width)
            context.move(to: CGPoint(x: x, y: origin.y))
            context.addLine(to: CGPoint(x: x, y: origin.y + rowHeight * CGFloat(rows.count)))
        }
        context.strokePath()
        for (rowIndex, row) in rows.enumerated() {
            var cellX = origin.x
            for (columnIndex, cell) in row.enumerated() {
                let font = NSFont.systemFont(ofSize: 15, weight: rowIndex == 0 ? .semibold : .regular)
                NSAttributedString(string: cell, attributes: [.font: font, .foregroundColor: NSColor.black])
                    .draw(at: CGPoint(x: cellX + 12, y: origin.y + CGFloat(rowIndex) * rowHeight + 11))
                cellX += columnWidths[columnIndex]
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
