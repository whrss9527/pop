import Foundation
@testable import Pop

/// 加密打包：把选中的文件和文件夹放进一个用密码加密的磁盘映像（.dmg，AES-256 或 AES-128），
/// 在任何一台 Mac 上双击、输入密码就能打开，像一个 U 盘。用系统的 hdiutil 做，密码从标准输入传过去，不出现在命令行里。
enum EncryptedImage {
    struct Failure: Error, Equatable {
        let message: String
    }

    enum Strength: String, CaseIterable, Identifiable {
        case aes256
        case aes128

        var id: String { rawValue }

        var title: String {
            switch self {
            case .aes256: return "AES-256"
            case .aes128: return "AES-128"
            }
        }

        var argument: String {
            switch self {
            case .aes256: return "AES-256"
            case .aes128: return "AES-128"
            }
        }
    }

    /// 密码至少几位
    static let minimumPassword = 4

    /// 密码怎么样：太短时不让做，短于 8 位或者只有一种字符时提醒一下；没问题时为 nil
    static func passwordHint(_ password: String, confirm: String) -> (message: String, blocking: Bool)? {
        if password.count < minimumPassword {
            return (String(localized: "密码至少 \(String(minimumPassword)) 位"), true)
        }
        if password != confirm {
            return (String(localized: "两次输入的密码不一样"), true)
        }
        if password.contains("\0") {
            return (String(localized: "密码里不能有空字符"), true)
        }
        let kinds = [password.contains(where: \.isLetter), password.contains(where: \.isNumber),
                     password.contains { !$0.isLetter && !$0.isNumber }].filter { $0 }.count
        if password.count < 8 || kinds < 2 {
            return (String(localized: "密码有点简单：8 位以上，字母、数字、符号混着用更安全"), false)
        }
        return nil
    }

    /// 映像的名字：一个文件夹就用它的名字，一个文件用不带扩展名的名字，几个用「n 项」
    static func defaultName(for items: [URL]) -> String {
        guard items.count == 1, let item = items.first else {
            return String(localized: "\(String(items.count)) 项")
        }
        return item.hasDirectoryPath || FolderTree.isFolder(item.path(percentEncoded: false))
            ? item.lastPathComponent : item.deletingPathExtension().lastPathComponent
    }

    /// 放进映像的那些东西一共多大（字节）
    static func size(of items: [URL]) -> Int64 {
        items.reduce(Int64(0)) { total, item in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path(percentEncoded: false), isDirectory: &isDirectory) else { return total }
            guard isDirectory.boolValue else {
                return total + Int64((try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
            }
            let enumerator = FileManager.default.enumerator(at: item, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], errorHandler: nil)
            var sum = total
            while let file = enumerator?.nextObject() as? URL {
                sum += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
            }
            return sum
        }
    }

    /// 映像的卷名：去掉「/」「:」，空的叫「加密」
    static func volumeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? String(localized: "加密") : String(cleaned.prefix(27))
    }

    /// hdiutil 的参数（不含密码）
    static func arguments(source: URL, output: URL, volume: String, strength: Strength) -> [String] {
        ["create", "-quiet", "-volname", volume, "-srcfolder", source.path(percentEncoded: false), "-fs", "APFS",
         "-encryption", strength.argument, "-stdinpass", "-format", "UDZO", "-ov", output.path(percentEncoded: false)]
    }

    /// 做加密映像，返回存好的 .dmg。一个文件夹直接用它（映像里就是它里面的东西）；
    /// 别的情况先在临时文件夹里放好副本（APFS 上是克隆，不占地方）
    static func create(_ items: [URL], name: String, password: String, strength: Strength = .aes256,
                       in folder: URL) async throws -> URL {
        guard !items.isEmpty else { throw Failure(message: String(localized: "没有选中文件")) }
        let output = FileNames.available(in: folder, base: volumeName(name), extension: "dmg")
        let staging = FileManager.default.temporaryDirectory.appending(path: "pop-encrypt-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: staging) }
        let source: URL
        if items.count == 1, FolderTree.isFolder(items[0].path(percentEncoded: false)) {
            source = items[0]
        } else {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for item in items {
                try FileManager.default.copyItem(at: item, to: staging.appending(path: item.lastPathComponent))
            }
            source = staging
        }
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"),
                                             arguments: arguments(source: source, output: output, volume: volumeName(name), strength: strength),
                                             stdin: password + "\0", environment: [:], timeout: 3600)
        switch result {
        case .failure(let error):
            try? FileManager.default.removeItem(at: output)
            throw Failure(message: String(localized: "加密打包失败：\(error.message)"))
        case .success(let run):
            guard run.status == 0, !run.timedOut, FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) else {
                try? FileManager.default.removeItem(at: output)
                let detail = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw Failure(message: String(localized: "加密打包失败：\(detail.isEmpty ? String(run.status) : detail)"))
            }
            return output
        }
    }

    /// 映像是不是加密的（hdiutil isencrypted）
    /// 刚做好的映像有时还被系统占着，hdiutil 会出错退出：等半秒再看，最多看三次。超时的不再等
    static func isEncrypted(_ image: URL) async -> Bool {
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard case .success(let run) = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"),
                                                                   arguments: ["isencrypted", image.path(percentEncoded: false)],
                                                                   stdin: nil, environment: [:], timeout: 60) else { return false }
            if run.status == 0 {
                return run.stdout.contains("encrypted: YES")
            }
            if run.timedOut {
                return false
            }
        }
        return false
    }
}
