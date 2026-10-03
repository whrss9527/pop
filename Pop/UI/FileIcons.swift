import AppKit

/// App、文件的图标。NSWorkspace 第一次取一个图标要读 App 包里的图标文件，一张卡片上一下子取十几个（打开方式），
/// 主线程要等好一会儿：先在后台取好、按要显示的大小画成位图记着，界面上直接用记着的
enum FileIcons {
    private static let cache = NSCache<NSString, NSImage>()

    /// 记着的图标；没记着时当场取（在主线程上会慢，先用 preload 在后台取好）
    static func icon(forFile path: String, size: CGFloat) -> NSImage {
        let key = "\(size)|\(path)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let icon = rendered(NSWorkspace.shared.icon(forFile: path), size: size)
        cache.setObject(icon, forKey: key)
        return icon
    }

    /// 在后台先取好这些文件（App）的图标
    static func preload(_ paths: [String], size: CGFloat) async {
        await runInBackground {
            for path in paths {
                _ = icon(forFile: path, size: size)
            }
        }
    }

    /// 按 size（点）在 2 倍屏上画成一张位图：之后在主线程上画的是现成的位图，不用再去读图标文件
    static func rendered(_ icon: NSImage, size: CGFloat) -> NSImage {
        let pixels = Int((size * 2).rounded(.up))
        guard pixels > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return icon }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
