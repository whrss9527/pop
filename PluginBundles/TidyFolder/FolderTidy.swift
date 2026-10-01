import Foundation
import UniformTypeIdentifiers
@testable import Pop

/// 整理文件夹：把一个文件夹第一层的文件按类型（图片、文档、压缩包……）或者按放进来的月份归到子文件夹里。
/// 子文件夹、隐藏文件和正在下载的文件不动；先算出计划给人看，整理完可以撤销。
enum FolderTidy {
    enum Mode: String, CaseIterable, Identifiable {
        case kind
        case month

        var id: String { rawValue }

        var title: String {
            switch self {
            case .kind: return String(localized: "按类型")
            case .month: return String(localized: "按月份")
            }
        }
    }

    enum Kind: String, CaseIterable {
        case images
        case videos
        case audio
        case documents
        case archives
        case installers
        case others

        /// 子文件夹的名字
        var title: String {
            switch self {
            case .images: return String(localized: "图像")
            case .videos: return String(localized: "视频")
            case .audio: return String(localized: "音频")
            case .documents: return String(localized: "文档")
            case .archives: return String(localized: "压缩包")
            case .installers: return String(localized: "安装包")
            case .others: return String(localized: "其他")
            }
        }

        var symbol: String {
            switch self {
            case .images: return "photo"
            case .videos: return "film"
            case .audio: return "waveform"
            case .documents: return "doc.text"
            case .archives: return "archivebox"
            case .installers: return "shippingbox"
            case .others: return "questionmark.folder"
            }
        }
    }

    struct Item: Equatable {
        let url: URL
        let isDirectory: Bool
        /// 放进这个文件夹的时间（「下载」里就是下载的时间）；没有时用修改时间
        let added: Date?
    }

    struct Move: Equatable {
        let from: URL
        let to: URL
    }

    struct Group: Equatable, Identifiable {
        /// 子文件夹的名字
        let name: String
        let symbol: String
        var count: Int

        var id: String { name }
    }

    struct Plan: Equatable {
        var moves: [Move]
        var groups: [Group]
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    /// 整理好了：挪了哪些、新建了哪些子文件夹（撤销用）
    struct Done: Equatable {
        var moves: [Move] = []
        var createdFolders: [URL] = []
    }

    /// 还没下载完的文件
    static let partialExtensions: Set<String> = ["crdownload", "part", "download", "partial", "opdownload"]
    static let documentExtensions: Set<String> = ["pdf", "doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key",
                                                  "txt", "rtf", "md", "markdown", "csv", "tsv", "epub", "mobi", "odt", "ods", "odp", "json", "xml", "html", "htm"]
    static let archiveExtensions: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst"]
    static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "ipa", "apk", "xip"]

    static func kind(of url: URL) -> Kind {
        let ext = url.pathExtension.lowercased()
        if installerExtensions.contains(ext) { return .installers }
        if archiveExtensions.contains(ext) { return .archives }
        if documentExtensions.contains(ext) { return .documents }
        guard let type = UTType(filenameExtension: ext) else { return .others }
        if type.conforms(to: .image) { return .images }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .text) || type.conforms(to: .compositeContent) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) {
            return .documents
        }
        return .others
    }

    /// 「2026-09」
    static func month(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// 哪些文件要挪、挪到哪个子文件夹。按类型时子文件夹按固定的顺序排，按月份时新的月份在前
    static func plan(_ items: [Item], in folder: URL, mode: Mode, calendar: Calendar = .current) -> Plan {
        var planned: [String: Set<String>] = [:]
        var moves: [Move] = []
        var counts: [String: Int] = [:]
        var symbols: [String: String] = [:]
        for item in items.sorted(by: { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }) {
            let name = item.url.lastPathComponent
            guard !item.isDirectory, !name.hasPrefix("."), !partialExtensions.contains(item.url.pathExtension.lowercased()) else { continue }
            let group: String
            let symbol: String
            switch mode {
            case .kind:
                let kind = kind(of: item.url)
                group = kind.title
                symbol = kind.symbol
            case .month:
                guard let added = item.added else { continue }
                group = month(of: added, calendar: calendar)
                symbol = "calendar"
            }
            // 和子文件夹同名的文件不动（比如已经有个叫「图片」的文件）
            guard group.lowercased() != name.lowercased() else { continue }
            let target = folder.appending(path: group, directoryHint: .isDirectory)
            var used = planned[group, default: existingNames(in: target)]
            let destination = target.appending(path: available(name, used: used))
            used.insert(destination.lastPathComponent.lowercased())
            planned[group] = used
            moves.append(Move(from: item.url, to: destination))
            counts[group, default: 0] += 1
            symbols[group] = symbol
        }
        let order: [String]
        switch mode {
        case .kind: order = Kind.allCases.map(\.title).filter { counts[$0] != nil }
        case .month: order = counts.keys.sorted(by: >)
        }
        return Plan(moves: moves, groups: order.map { Group(name: $0, symbol: symbols[$0] ?? "folder", count: counts[$0] ?? 0) })
    }

    /// 子文件夹里已经有的名字（小写，用来避开重名）
    private static func existingNames(in folder: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return Set(names.map { $0.lowercased() })
    }

    /// 重名时在后面加 2、3……（扩展名不变）
    static func available(_ name: String, used: Set<String>) -> String {
        guard used.contains(name.lowercased()) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !used.contains(candidate.lowercased()) { return candidate }
            counter += 1
        }
    }

    /// 文件夹第一层的东西
    static func items(in folder: URL) throws -> [Item] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .addedToDirectoryDateKey, .contentModificationDateKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
        } catch {
            throw Failure(message: String(localized: "读不了「\(folder.lastPathComponent)」：\(error.localizedDescription)"))
        }
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            // App 和其他包看起来是文件，其实是文件夹：不动
            return Item(url: url, isDirectory: values?.isDirectory ?? false,
                        added: values?.addedToDirectoryDate ?? values?.contentModificationDate)
        }
    }

    /// 按计划挪。中途出错时先把挪了的挪回去再报错
    static func apply(_ plan: Plan) throws -> Done {
        var done = Done()
        for move in plan.moves {
            do {
                let folder = move.to.deletingLastPathComponent()
                if !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    done.createdFolders.append(folder)
                }
                try FileManager.default.moveItem(at: move.from, to: move.to)
                done.moves.append(move)
            } catch {
                try? undo(done)
                throw Failure(message: String(localized: "没能挪动「\(move.from.lastPathComponent)」：\(error.localizedDescription)"))
            }
        }
        return done
    }

    /// 撤销：挪回原来的地方，整理时新建的子文件夹空了就删掉
    static func undo(_ done: Done) throws {
        var failures: [String] = []
        for move in done.moves.reversed() {
            do {
                try FileManager.default.moveItem(at: move.to, to: move.from)
            } catch {
                failures.append(move.to.lastPathComponent)
            }
        }
        for folder in done.createdFolders {
            let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? ["?"]
            if left.allSatisfy({ $0 == ".DS_Store" }) {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        if let first = failures.first {
            throw Failure(message: String(localized: "有 \(failures.count) 个文件没能挪回去，比如「\(first)」"))
        }
    }
}
