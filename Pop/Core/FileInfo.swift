import AVFoundation
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// 文件的基本信息：类型、大小（文件夹算上里面所有文件）、创建和修改时间，
/// 另外图片列出尺寸和拍摄信息、PDF 列出页数、音视频列出时长和画面大小。
enum FileInfo {
    /// 文件夹最多数这么多个文件，太多就只给个大概
    static let folderLimit = 200_000

    struct FolderSize: Equatable {
        var bytes: Int64
        var files: Int
        /// 文件太多没数完
        var truncated: Bool
    }

    static func rows(for url: URL) async -> [ResultCard.Row] {
        let keys: Set<URLResourceKey> = [.contentTypeKey, .fileSizeKey, .isDirectoryKey, .isPackageKey, .creationDateKey,
                                         .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return [] }
        var rows: [ResultCard.Row] = []
        if let type = values.contentType {
            rows.append(ResultCard.Row(label: "类型", value: type.localizedDescription ?? type.identifier))
        }
        if values.isDirectory == true {
            let size = folderSize(url)
            let prefix = size.truncated ? "至少 " : ""
            rows.append(ResultCard.Row(label: "大小", value: prefix + describe(bytes: size.bytes)))
            rows.append(ResultCard.Row(label: "文件数", value: "\(prefix)\(size.files) 个"))
        } else if let bytes = values.fileSize {
            rows.append(ResultCard.Row(label: "大小", value: describe(bytes: Int64(bytes))))
        }
        if let created = values.creationDate {
            rows.append(ResultCard.Row(label: "创建时间", value: format(created)))
        }
        if let modified = values.contentModificationDate {
            rows.append(ResultCard.Row(label: "修改时间", value: format(modified)))
        }
        if let type = values.contentType, values.isDirectory != true {
            rows += await details(for: url, type: type)
        }
        rows.append(ResultCard.Row(label: "位置", value: abbreviated(url.deletingLastPathComponent())))
        return rows
    }

    /// 选了好几个文件：一共多少个、总共多大
    static func summary(for urls: [URL]) -> [ResultCard.Row] {
        var bytes: Int64 = 0
        var files = 0
        var truncated = false
        for url in urls {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDirectory {
                let size = folderSize(url)
                bytes += size.bytes
                files += size.files
                truncated = truncated || size.truncated
            } else {
                bytes += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                files += 1
            }
        }
        let prefix = truncated ? "至少 " : ""
        return [
            ResultCard.Row(label: "选中", value: "\(urls.count) 项"),
            ResultCard.Row(label: "文件数", value: "\(prefix)\(files) 个"),
            ResultCard.Row(label: "总大小", value: prefix + describe(bytes: bytes)),
        ]
    }

    static func folderSize(_ url: URL, limit: Int = folderLimit) -> FolderSize {
        var result = FolderSize(bytes: 0, files: 0, truncated: false)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                              options: [], errorHandler: { _, _ in true }) else { return result }
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            result.bytes += Int64(values.fileSize ?? 0)
            result.files += 1
            if result.files >= limit {
                result.truncated = true
                break
            }
        }
        return result
    }

    /// 1.2 MB（1,234,567 字节）
    static func describe(bytes: Int64) -> String {
        let readable = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        guard bytes >= 1000 else { return readable }
        let exact = NumberFormatter.localizedString(from: NSNumber(value: bytes), number: .decimal)
        return "\(readable)（\(exact) 字节）"
    }

    /// 1.2 MB（只要好读的写法）
    static func shortSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// 3725 秒 → 1:02:05
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    private static func details(for url: URL, type: UTType) async -> [ResultCard.Row] {
        if type.conforms(to: .image) {
            return ImageInfo.rows(for: url).filter { $0.label == "尺寸" } + (PhotoMetadata.read(url)?.rows ?? [])
        }
        if type.conforms(to: .pdf), let document = PDFDocument(url: url) {
            return [ResultCard.Row(label: "页数", value: "\(document.pageCount) 页")]
        }
        if type.conforms(to: .audiovisualContent) {
            let asset = AVURLAsset(url: url)
            var rows: [ResultCard.Row] = []
            if let time = try? await asset.load(.duration), time.seconds.isFinite, time.seconds > 0 {
                rows.append(ResultCard.Row(label: "时长", value: duration(time.seconds)))
            }
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize), size.width > 0 {
                rows.append(ResultCard.Row(label: "画面", value: "\(Int(size.width)) × \(Int(size.height))"))
            }
            return rows
        }
        return []
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 家目录换成 ~
    private static func abbreviated(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
