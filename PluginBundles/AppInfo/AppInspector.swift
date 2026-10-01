import Darwin
import Foundation
import Security
@testable import Pop

/// App 信息：版本、支持哪种芯片、谁签的名、有没有公证、在不在沙盒里、会要哪些权限、用什么做的、从哪来的。
enum AppInspector {
    struct Failure: Error, Equatable {
        let message: String
    }

    /// 可执行文件是给哪种芯片编译的
    enum Architecture: String, Equatable {
        case appleSilicon
        case intel
        case universal
        case unknown

        var title: String {
            switch self {
            case .appleSilicon: return String(localized: "Apple 芯片")
            case .intel: return "Intel"
            case .universal: return String(localized: "通用（Apple 芯片和 Intel）")
            case .unknown: return String(localized: "认不出")
            }
        }
    }

    /// 谁签的名
    enum Signature: Equatable {
        /// 系统自带的
        case apple
        case appStore
        /// 证书上的开发者名字
        case developerID(String)
        /// 开发、测试用的证书
        case development(String)
        /// 临时签名（没有证书）
        case adHoc
        case unsigned
        case other(String)

        var title: String {
            switch self {
            case .apple: return String(localized: "苹果")
            case .appStore: return "App Store"
            case .developerID(let name): return String(localized: "Developer ID：\(name)")
            case .development(let name): return String(localized: "开发证书：\(name)")
            case .adHoc: return String(localized: "临时签名（没有证书）")
            case .unsigned: return String(localized: "没有签名")
            case .other(let name): return name
            }
        }
    }

    /// Info.plist 里写了用途说明的权限
    struct Permission: Equatable, Identifiable {
        let name: String
        /// App 自己写的用途说明
        let reason: String

        var id: String { name }
    }

    struct Report: Equatable {
        let url: URL
        let name: String
        let bundleID: String?
        /// 「3.2.1（321）」
        let version: String?
        let architecture: Architecture
        let minimumSystem: String?
        let signature: Signature
        let teamID: String?
        /// 有没有公证；不需要公证的（苹果的、App Store 的、没签名的）为 nil
        let notarized: Bool?
        let sandboxed: Bool
        let hardenedRuntime: Bool
        /// 用什么做的：Electron、Flutter、Qt、Java、Mac Catalyst……还有 Sparkle 自动更新
        let technologies: [String]
        let permissions: [Permission]
        let urlSchemes: [String]
        let fromAppStore: Bool
        /// 从网上下载时，下载它的 App（隔离标记里记着）
        let downloadedBy: String?
    }

    static func inspect(_ url: URL) throws -> Report {
        guard url.pathExtension.lowercased() == "app", let bundle = Bundle(url: url) else {
            throw Failure(message: String(localized: "「\(url.lastPathComponent)」不是 App"))
        }
        let info = bundle.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        let version = versionText(short: short, build: build)
        let signed = signing(of: url)
        return Report(url: url,
                      name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent,
                      bundleID: info["CFBundleIdentifier"] as? String,
                      version: version,
                      architecture: bundle.executableURL.map(architecture(of:)) ?? .unknown,
                      minimumSystem: (info["LSMinimumSystemVersion"] as? String).map { "macOS \($0)" },
                      signature: signed.signature, teamID: signed.team, notarized: signed.notarized,
                      sandboxed: signed.sandboxed, hardenedRuntime: signed.hardened,
                      technologies: technologies(in: url, info: info),
                      permissions: permissions(in: info),
                      urlSchemes: urlSchemes(in: info),
                      fromAppStore: FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt/receipt").path(percentEncoded: false)),
                      downloadedBy: quarantineAgent(of: url))
    }

    // MARK: - 芯片

    static let cpuARM64: UInt32 = 0x0100_000C
    static let cpuX86_64: UInt32 = 0x0100_0007

    /// 读可执行文件开头的 Mach-O 头：通用二进制里列着每一种芯片，单一的看 cputype
    static func architecture(of executable: URL) -> Architecture {
        guard let handle = try? FileHandle(forReadingFrom: executable) else { return .unknown }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4096), header.count >= 8 else { return .unknown }
        return architecture(header: [UInt8](header))
    }

    static func architecture(header bytes: [UInt8]) -> Architecture {
        guard bytes.count >= 8 else { return .unknown }
        func bigEndian(_ offset: Int) -> UInt32 {
            guard offset + 4 <= bytes.count else { return 0 }
            return bytes[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        func littleEndian(_ offset: Int) -> UInt32 {
            guard offset + 4 <= bytes.count else { return 0 }
            return bytes[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }
        var types: Set<UInt32> = []
        switch bigEndian(0) {
        case 0xCAFE_BABE, 0xCAFE_BABF:
            // 通用二进制：大端，每一种 20 字节（64 位的是 32 字节），开头是 cputype
            let entry = bigEndian(0) == 0xCAFE_BABF ? 32 : 20
            for index in 0..<min(Int(bigEndian(4)), 16) {
                types.insert(bigEndian(8 + index * entry))
            }
        case 0xCFFA_EDFE, 0xCEFA_EDFE:
            // 单一的：小端
            types.insert(littleEndian(4))
        default:
            return .unknown
        }
        let arm = types.contains(cpuARM64)
        let intel = types.contains(cpuX86_64)
        if arm && intel { return .universal }
        if arm { return .appleSilicon }
        if intel { return .intel }
        return .unknown
    }

    // MARK: - 签名

    static func signing(of url: URL) -> (signature: Signature, team: String?, notarized: Bool?, sandboxed: Bool, hardened: Bool) {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return (.unsigned, nil, nil, false, false) }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation) | UInt32(kSecCSRequirementInformation))
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              dictionary[kSecCodeInfoIdentifier as String] != nil else { return (.unsigned, nil, nil, false, false) }
        let codeFlags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let sandboxed = entitlements?["com.apple.security.app-sandbox"] as? Bool == true
        // kSecCodeSignatureAdhoc、kSecCodeSignatureRuntime
        let adHoc = codeFlags & 0x0002 != 0
        let hardened = codeFlags & 0x1_0000 != 0
        let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
        let leaf = certificates.first.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? ""
        let signature = classify(leaf: leaf, adHoc: adHoc)
        var notarized: Bool?
        if case .developerID = signature {
            // 只看签名和公证票据，不逐个校验资源文件（大 App 会很慢）
            var requirement: SecRequirement?
            if SecRequirementCreateWithString("notarized" as CFString, [], &requirement) == errSecSuccess, let requirement {
                notarized = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: UInt32(kSecCSDoNotValidateResources)), requirement) == errSecSuccess
            }
        }
        return (signature, team, notarized, sandboxed, hardened)
    }

    /// 按证书的名字分：「Developer ID Application: 名字 (团队)」「Apple Mac OS Application Signing」（App Store）「Software Signing」（苹果）……
    static func classify(leaf: String, adHoc: Bool) -> Signature {
        if adHoc || leaf.isEmpty { return adHoc ? .adHoc : .unsigned }
        func holder(after prefix: String) -> String {
            var name = String(leaf.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            // 去掉后面的「(团队 ID)」
            if let open = name.lastIndex(of: "("), name.hasSuffix(")") {
                name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
            }
            return name
        }
        if leaf.hasPrefix("Developer ID Application:") { return .developerID(holder(after: "Developer ID Application:")) }
        if leaf == "Apple Mac OS Application Signing" { return .appStore }
        if leaf == "Software Signing" || leaf.hasPrefix("Apple ") && !leaf.contains(":") { return .apple }
        for prefix in ["Apple Development:", "Mac Developer:", "Apple Distribution:", "3rd Party Mac Developer Application:"] where leaf.hasPrefix(prefix) {
            return .development(holder(after: prefix))
        }
        return .other(leaf)
    }

    // MARK: - Info.plist 和包里的东西

    /// 会要的权限：Info.plist 里写了用途说明的那几项，按名字去重（日历、提醒事项新旧两种写法算一个）
    static func permissions(in info: [String: Any]) -> [Permission] {
        let keys: [(String, String)] = [
            ("NSCameraUsageDescription", String(localized: "摄像头")),
            ("NSMicrophoneUsageDescription", String(localized: "麦克风")),
            ("NSScreenCaptureUsageDescription", String(localized: "屏幕录制")),
            ("NSContactsUsageDescription", String(localized: "通讯录")),
            ("NSCalendarsFullAccessUsageDescription", String(localized: "日历")),
            ("NSCalendarsUsageDescription", String(localized: "日历")),
            ("NSRemindersFullAccessUsageDescription", String(localized: "提醒事项")),
            ("NSRemindersUsageDescription", String(localized: "提醒事项")),
            ("NSPhotoLibraryUsageDescription", String(localized: "照片")),
            ("NSLocationUsageDescription", String(localized: "位置")),
            ("NSLocationWhenInUseUsageDescription", String(localized: "位置")),
            ("NSLocationAlwaysAndWhenInUseUsageDescription", String(localized: "位置")),
            ("NSBluetoothAlwaysUsageDescription", String(localized: "蓝牙")),
            ("NSLocalNetworkUsageDescription", String(localized: "本地网络")),
            ("NSSpeechRecognitionUsageDescription", String(localized: "语音识别")),
            ("NSAppleEventsUsageDescription", String(localized: "控制别的 App")),
            ("NSDesktopFolderUsageDescription", String(localized: "桌面文件夹")),
            ("NSDocumentsFolderUsageDescription", String(localized: "文稿文件夹")),
            ("NSDownloadsFolderUsageDescription", String(localized: "下载文件夹")),
            ("NSRemovableVolumesUsageDescription", String(localized: "U 盘和移动硬盘")),
            ("NSHomeKitUsageDescription", String(localized: "家庭")),
            ("NSSystemAdministrationUsageDescription", String(localized: "管理员权限")),
        ]
        var seen: Set<String> = []
        return keys.compactMap { key, name in
            guard let reason = info[key] as? String, seen.insert(name).inserted else { return nil }
            return Permission(name: name, reason: reason)
        }
    }

    /// 能用来打开它的链接开头（「sketchpad://」）
    static func urlSchemes(in info: [String: Any]) -> [String] {
        let types = info["CFBundleURLTypes"] as? [[String: Any]] ?? []
        var schemes: [String] = []
        for type in types {
            for scheme in type["CFBundleURLSchemes"] as? [String] ?? [] where !schemes.contains(scheme) {
                schemes.append(scheme)
            }
        }
        return schemes.map { "\($0)://" }
    }

    /// 用什么做的：看包里带的框架和文件
    static func technologies(in app: URL, info: [String: Any]) -> [String] {
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        func exists(_ path: String) -> Bool {
            FileManager.default.fileExists(atPath: contents.appending(path: path).path(percentEncoded: false))
        }
        var found: [String] = []
        if exists("Frameworks/Electron Framework.framework") || exists("Resources/app.asar") { found.append("Electron") }
        if exists("Frameworks/FlutterMacOS.framework") { found.append("Flutter") }
        if exists("Frameworks/QtCore.framework") { found.append("Qt") }
        if exists("Frameworks/Chromium Embedded Framework.framework") { found.append(String(localized: "Chromium 内核")) }
        if exists("Frameworks/UnityPlayer.dylib") { found.append("Unity") }
        if exists("Java") || exists("runtime") || exists("PlugIns/Java.runtime") { found.append("Java") }
        if info["UIDeviceFamily"] != nil {
            let wrapped = FileManager.default.fileExists(atPath: app.appending(path: "Wrapper").path(percentEncoded: false))
            found.append(wrapped ? String(localized: "iPhone、iPad App") : "Mac Catalyst")
        }
        if exists("Frameworks/Sparkle.framework") { found.append(String(localized: "Sparkle 自动更新")) }
        return found
    }

    /// 隔离标记（com.apple.quarantine）里记着下载它的 App，比如「0083;66f1a2b3;Safari;…」
    static func quarantineAgent(of url: URL) -> String? {
        let path = url.path(percentEncoded: false)
        let name = "com.apple.quarantine"
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(path, name, &buffer, length, 0, 0) == length else { return nil }
        let fields = String(decoding: buffer, as: UTF8.self).split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count > 2 else { return nil }
        let agent = fields[2].trimmingCharacters(in: .whitespaces)
        return agent.isEmpty ? nil : agent
    }

    /// 文件夹占的空间（字节）
    static func size(of url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += UInt64(max(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0, 0))
        }
        return total
    }

    // MARK: - 写成文字

    /// 「3.2.1（321）」：编译号和版本号一样时只写一个；括号跟着界面语言
    static func versionText(short: String?, build: String?) -> String? {
        guard let short else { return build }
        guard let build, build != short else { return short }
        return String(localized: "\(short)（\(build)）")
    }

    /// 「Developer ID：Example Studio（ABCDE12345）」：后面带上团队 ID
    static func signatureText(_ report: Report) -> String {
        report.teamID.map { String(localized: "\(report.signature.title)（\($0)）") } ?? report.signature.title
    }

    /// 复制用的一段文字，一行一项
    static func text(_ report: Report, size: UInt64?) -> String {
        var lines = [report.name + (report.version.map { " \($0)" } ?? "")]
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty { lines.append(String(localized: "\(label)：\(value)")) }
        }
        add(String(localized: "标识符"), report.bundleID)
        add(String(localized: "芯片"), report.architecture.title)
        add(String(localized: "最低系统"), report.minimumSystem)
        add(String(localized: "签名"), signatureText(report))
        add(String(localized: "公证"), report.notarized.map { $0 ? String(localized: "已公证") : String(localized: "没有公证") })
        add(String(localized: "沙盒"), report.sandboxed ? String(localized: "在沙盒里") : String(localized: "不在沙盒里"))
        add(String(localized: "加固运行时"), report.hardenedRuntime ? String(localized: "开着") : String(localized: "没开"))
        add(String(localized: "用什么做的"), report.technologies.joined(separator: " · "))
        add(String(localized: "来源"), source(report))
        add(String(localized: "大小"), size.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) })
        add(String(localized: "会要的权限"), report.permissions.map(\.name).joined(separator: String(localized: "、")))
        add(String(localized: "打开它的链接"), report.urlSchemes.joined(separator: " "))
        return lines.joined(separator: "\n")
    }

    /// 从哪来的：App Store、某个 App 下载的
    static func source(_ report: Report) -> String? {
        if report.fromAppStore { return "App Store" }
        if let agent = report.downloadedBy { return String(localized: "用「\(agent)」下载的") }
        if case .apple = report.signature { return String(localized: "系统自带") }
        return nil
    }
}
