import AVFoundation
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// 视频缩略图：从头到尾均匀取 16 帧，4 列排成一张图，每格右下角标上时间；最上面写文件名、时长、画面大小和文件大小
enum ContactSheet {
    static let columns = 4
    static let frameCount = 16

    struct Layout: Equatable {
        var thumbnail: CGSize
        var columns: Int
        var rows: Int
        var margin: CGFloat = 24
        var gap: CGFloat = 12
        /// 标题和说明占的高度
        var header: CGFloat = 64

        var size: CGSize {
            CGSize(width: margin * 2 + CGFloat(columns) * thumbnail.width + CGFloat(columns - 1) * gap,
                   height: margin * 2 + header + CGFloat(rows) * thumbnail.height + CGFloat(rows - 1) * gap)
        }

        /// 第 index 格的位置（左下角为原点，和 CGContext 一致），从左上角开始一行一行排
        func frame(at index: Int) -> CGRect {
            let column = index % columns
            let row = index / columns
            let top = margin + header + CGFloat(row) * (thumbnail.height + gap)
            return CGRect(x: margin + CGFloat(column) * (thumbnail.width + gap), y: size.height - top - thumbnail.height,
                          width: thumbnail.width, height: thumbnail.height)
        }
    }

    /// 按画面大小排版：横的画面每格宽 480，竖的 300；小视频不放大那么多，但每格至少 160 宽
    static func layout(videoSize: CGSize, count: Int = frameCount) -> Layout {
        let landscape = videoSize.width >= videoSize.height
        let width = max(160, min(landscape ? 480 : 300, videoSize.width)).rounded()
        let aspect = videoSize.width > 0 && videoSize.height > 0 ? videoSize.height / videoSize.width : 9.0 / 16.0
        let columns = min(Self.columns, max(count, 1))
        return Layout(thumbnail: CGSize(width: width, height: (width * aspect).rounded()), columns: columns,
                      rows: (max(count, 1) + columns - 1) / columns)
    }

    /// 均匀取的时间点（秒）：把视频分成 count 段，取每段的中间
    static func times(duration: Double, count: Int = frameCount) -> [Double] {
        guard duration > 0, count > 0 else { return [] }
        return (0..<count).map { (Double($0) + 0.5) / Double(count) * duration }
    }

    /// 生成缩略图，存成 JPEG
    static func make(from asset: AVURLAsset, name: String, fileSize: Int?, to output: URL) async throws {
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw VideoConverter.Failure(message: "读不到视频的时长") }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoConverter.Failure(message: "这个文件里没有画面")
        }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        // 手机竖着拍的视频画面是横着存的，按播放时的方向算
        let upright = natural.applying(transform)
        let videoSize = CGSize(width: abs(upright.width), height: abs(upright.height))
        let sheet = layout(videoSize: videoSize)
        let size = sheet.size
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw VideoConverter.Failure(message: "缩略图太大了，画不出来")
        }
        context.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        var details = ["时长 \(FileInfo.duration(duration))", "\(Int(videoSize.width.rounded())) × \(Int(videoSize.height.rounded()))"]
        if let fileSize {
            details.append(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
        }
        drawHeader(in: context, layout: sheet, title: name, detail: details.joined(separator: " · "))

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = sheet.thumbnail
        // 不用正好在那个时间点上，附近的帧就行，快很多
        let tolerance = CMTime(seconds: duration / Double(frameCount) / 4, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var index = 0
        var drawn = 0
        for await result in generator.images(for: times(duration: duration).map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            try Task.checkCancellation()
            let cell = sheet.frame(at: index)
            index += 1
            switch result {
            case .success(requestedTime: _, image: let image, actualTime: let actual):
                context.draw(image, in: fit(CGSize(width: image.width, height: image.height), in: cell))
                drawTime(actual.seconds, in: context, cell: cell)
                drawn += 1
            case .failure(requestedTime: _, error: _):
                // 这一帧取不出来：留一个浅一点的空格
                context.setFillColor(CGColor(srgbRed: 0.18, green: 0.18, blue: 0.19, alpha: 1))
                context.fill(cell)
            }
        }
        guard drawn > 0 else { throw VideoConverter.Failure(message: "没能从视频里取出画面") }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw VideoConverter.Failure(message: "存储缩略图失败")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw VideoConverter.Failure(message: "存储缩略图失败") }
    }

    /// 按比例放进格子里，居中
    static func fit(_ size: CGSize, in cell: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return cell }
        let scale = min(cell.width / size.width, cell.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: cell.midX - width / 2, y: cell.midY - height / 2, width: width, height: height)
    }

    private static func line(_ text: String, size: CGFloat, bold: Bool, gray: CGFloat) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// 太长的一行在末尾截成「…」
    private static func truncated(_ line: CTLine, width: CGFloat, size: CGFloat, gray: CGFloat) -> CTLine {
        let ellipsis = self.line("…", size: size, bold: false, gray: gray)
        return CTLineCreateTruncatedLine(line, Double(width), .end, ellipsis) ?? line
    }

    private static func drawHeader(in context: CGContext, layout: Layout, title: String, detail: String) {
        let width = layout.size.width - layout.margin * 2
        let top = layout.size.height - layout.margin
        let titleLine = truncated(line(title, size: 20, bold: true, gray: 1), width: width, size: 20, gray: 1)
        let detailLine = truncated(line(detail, size: 14, bold: false, gray: 0.68), width: width, size: 14, gray: 0.68)
        context.textPosition = CGPoint(x: layout.margin, y: top - 22)
        CTLineDraw(titleLine, context)
        context.textPosition = CGPoint(x: layout.margin, y: top - 48)
        CTLineDraw(detailLine, context)
    }

    /// 格子右下角的时间
    private static func drawTime(_ seconds: Double, in context: CGContext, cell: CGRect) {
        guard seconds.isFinite else { return }
        let text = line(FileInfo.duration(seconds), size: 13, bold: true, gray: 1)
        let bounds = CTLineGetBoundsWithOptions(text, [])
        let box = CGRect(x: cell.maxX - bounds.width - 16, y: cell.minY + 6, width: bounds.width + 10, height: 20)
        context.setFillColor(CGColor(gray: 0, alpha: 0.6))
        context.addPath(CGPath(roundedRect: box, cornerWidth: 5, cornerHeight: 5, transform: nil))
        context.fillPath()
        context.textPosition = CGPoint(x: box.minX + 5, y: box.minY + 6)
        CTLineDraw(text, context)
    }
}
