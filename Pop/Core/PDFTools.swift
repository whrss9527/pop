import AppKit
import PDFKit

/// PDF 的合成、拆成图片、取文字、压缩。
enum PDFTools {
    struct Failure: Error, Equatable {
        let message: String
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// 按文件名排好顺序（「第 2 页」排在「第 10 页」前面）
    static func sorted(_ files: [URL]) -> [URL] {
        files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw Failure(message: String(localized: "读不了「\(url.lastPathComponent)」"))
        }
        guard !document.isLocked else {
            throw Failure(message: String(localized: "「\(url.lastPathComponent)」有密码，先解锁再处理"))
        }
        return document
    }

    /// 按顺序把 PDF 的每一页和图片（一张一页）合成一个 PDF，返回总页数
    @discardableResult
    static func combine(_ files: [URL], into destination: URL) throws -> Int {
        let output = PDFDocument()
        for file in files {
            if isPDF(file) {
                let document = try open(file)
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index)?.copy() as? PDFPage else { continue }
                    output.insert(page, at: output.pageCount)
                }
            } else {
                guard let image = NSImage(contentsOf: file), let page = PDFPage(image: image) else {
                    throw Failure(message: String(localized: "读不了「\(file.lastPathComponent)」"))
                }
                output.insert(page, at: output.pageCount)
            }
        }
        guard output.pageCount > 0 else { throw Failure(message: String(localized: "没有可以合成的页面")) }
        guard output.write(to: destination) else { throw Failure(message: String(localized: "写不进「\(destination.lastPathComponent)」")) }
        return output.pageCount
    }

    /// 把 PDF 的每一页存成 PNG（按页面大小的 scale 倍像素），放进 folder，返回这些文件
    static func exportPages(of pdf: URL, to folder: URL, scale: CGFloat = 2) throws -> [URL] {
        let document = try open(pdf)
        guard document.pageCount > 0 else { throw Failure(message: String(localized: "「\(pdf.lastPathComponent)」里没有页面")) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = pdf.deletingPathExtension().lastPathComponent
        let digits = max(String(document.pageCount).count, 2)
        var outputs: [URL] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let png = render(page, scale: scale) else {
                throw Failure(message: String(localized: "第 \(index + 1) 页渲染失败"))
            }
            let number = String(repeating: "0", count: max(digits - String(index + 1).count, 0)) + String(index + 1)
            let url = folder.appending(path: "\(base)-\(number).png")
            try png.write(to: url)
            outputs.append(url)
        }
        return outputs
    }

    /// 一页渲染成白底的 PNG（按页面的旋转方向）
    static func render(_ page: PDFPage, scale: CGFloat) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        let rotated = abs(page.rotation) % 180 == 90
        let size = rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, width * height <= 100_000_000,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        let thumbnail = page.thumbnail(of: canvas.size, for: .mediaBox)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: canvas).fill()
        thumbnail.draw(in: canvas)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    struct Compression: Equatable {
        var url: URL
        var before: Int64
        var after: Int64

        /// 至少小了一成才算压缩了
        var worthwhile: Bool { after < before - before / 10 }
    }

    /// 压缩 PDF：里面的图片存成 JPEG、按屏幕显示的清晰度缩小，另存成「原名 压缩.pdf」
    static func compress(_ pdf: URL) throws -> Compression {
        let document = try open(pdf)
        let output = FileNames.available(in: pdf.deletingLastPathComponent(),
                                         base: pdf.deletingPathExtension().lastPathComponent + String(localized: " 压缩"), extension: "pdf")
        let options: [PDFDocumentWriteOption: Any] = [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]
        guard document.write(to: output, withOptions: options) else {
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "写不进「\(output.lastPathComponent)」"))
        }
        func size(_ url: URL) -> Int64 {
            Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return Compression(url: output, before: size(pdf), after: size(output))
    }

    /// 「1-3, 5, 8-」这样的页码（从 1 数），返回从 0 开始的页码，顺序照写的来；写错或者超出范围时返回 nil
    static func pageIndices(_ text: String, pageCount: Int) -> [Int]? {
        guard pageCount > 0 else { return nil }
        var result: [Int] = []
        let normalized = text.replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",")
            .replacingOccurrences(of: "～", with: "-").replacingOccurrences(of: "~", with: "-").replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "－", with: "-").replacingOccurrences(of: "到", with: "-")
        for rawPart in normalized.split(separator: ",") {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { continue }
            let pieces = part.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            switch pieces.count {
            case 1:
                guard let page = Int(pieces[0]), (1...pageCount).contains(page) else { return nil }
                result.append(page - 1)
            case 2:
                // 「-3」是开头到第 3 页，「8-」是第 8 页到最后
                guard let start = pieces[0].isEmpty ? 1 : Int(pieces[0]), let end = pieces[1].isEmpty ? pageCount : Int(pieces[1]),
                      1 <= start, start <= end, end <= pageCount else { return nil }
                result += (start...end).map { $0 - 1 }
            default:
                return nil
            }
        }
        return result.isEmpty ? nil : result
    }

    /// 取出这几页（按给的顺序）存成新的 PDF
    static func extract(_ pdf: URL, pages: [Int], to destination: URL) throws {
        try write(pages, of: try open(pdf), to: destination)
    }

    private static func write(_ pages: [Int], of document: PDFDocument, to destination: URL) throws {
        let output = PDFDocument()
        for index in pages {
            guard let page = document.page(at: index)?.copy() as? PDFPage else {
                throw Failure(message: String(localized: "没有第 \(index + 1) 页"))
            }
            output.insert(page, at: output.pageCount)
        }
        guard output.pageCount > 0 else { throw Failure(message: String(localized: "没有选中页面")) }
        guard output.write(to: destination) else { throw Failure(message: String(localized: "写不进「\(destination.lastPathComponent)」")) }
    }

    /// 每一页存成一个 PDF，放进 folder，返回这些文件
    static func split(_ pdf: URL, to folder: URL) throws -> [URL] {
        let document = try open(pdf)
        guard document.pageCount > 0 else { throw Failure(message: String(localized: "「\(pdf.lastPathComponent)」里没有页面")) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = pdf.deletingPathExtension().lastPathComponent
        let digits = max(String(document.pageCount).count, 2)
        var outputs: [URL] = []
        for index in 0..<document.pageCount {
            let number = String(repeating: "0", count: max(digits - String(index + 1).count, 0)) + String(index + 1)
            let url = folder.appending(path: "\(base)-\(number).pdf")
            try write([index], of: document, to: url)
            outputs.append(url)
        }
        return outputs
    }

    /// 打开时要输入密码
    static func isLocked(_ pdf: URL) -> Bool {
        PDFDocument(url: pdf)?.isLocked == true
    }

    /// 加上打开密码（修改权限也用同一个密码），另存一份
    static func encrypt(_ pdf: URL, password: String, to destination: URL) throws {
        guard !password.isEmpty else { throw Failure(message: String(localized: "密码不能是空的")) }
        let document = try open(pdf)
        let options: [PDFDocumentWriteOption: Any] = [.userPasswordOption: password, .ownerPasswordOption: password]
        guard document.write(to: destination, withOptions: options) else {
            throw Failure(message: String(localized: "写不进「\(destination.lastPathComponent)」"))
        }
    }

    /// 用密码打开，另存一份没有密码的。只知道打开密码、PDF 还限制了打印复制这些的，不去掉
    static func removePassword(_ pdf: URL, password: String, to destination: URL) throws {
        guard let document = PDFDocument(url: pdf) else { throw Failure(message: String(localized: "读不了「\(pdf.lastPathComponent)」")) }
        guard document.isEncrypted else { throw Failure(message: String(localized: "「\(pdf.lastPathComponent)」没有密码")) }
        guard document.unlock(withPassword: password) else { throw Failure(message: String(localized: "密码不对")) }
        let permissions = [document.allowsPrinting, document.allowsCopying, document.allowsDocumentChanges,
                           document.allowsContentAccessibility, document.allowsCommenting, document.allowsFormFieldEntry,
                           document.allowsDocumentAssembly]
        guard document.permissionsStatus == .owner || !permissions.contains(false) else {
            throw Failure(message: String(localized: "这份 PDF 还限制了打印、复制这些操作，要输入所有者密码才能去掉"))
        }
        // 解开之后另存出来的就没有加密；万一还带着密码，就把每一页拷到新文件里
        if document.write(to: destination), PDFDocument(url: destination)?.isEncrypted == false {
            return
        }
        try? FileManager.default.removeItem(at: destination)
        try write(Array(0..<document.pageCount), of: document, to: destination)
        guard PDFDocument(url: destination)?.isEncrypted == false else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure(message: String(localized: "没能去掉密码"))
        }
    }

    /// 页码写法的简短说明：「第 1–3、5 页」
    static func describe(_ pages: [Int]) -> String {
        var ranges: [String] = []
        var index = 0
        while index < pages.count {
            var end = index
            while end + 1 < pages.count, pages[end + 1] == pages[end] + 1 {
                end += 1
            }
            ranges.append(end > index ? "\(pages[index] + 1)–\(pages[end] + 1)" : "\(pages[index] + 1)")
            index = end + 1
        }
        let list = ranges.joined(separator: Localization.listSeparator)
        return String(localized: "第 \(list) 页")
    }

    /// PDF 里的全部文字（扫描件没有文字层时为空）
    static func text(of pdf: URL) -> String {
        (try? open(pdf))?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
