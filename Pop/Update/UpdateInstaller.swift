import CryptoKit
import Foundation
import Security

/// shasum -a 256 输出的校验文件：每行「哈希  文件名」。
enum Checksums {
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let hash = parts[0].lowercased()
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else { continue }
            var name = parts[1...].joined(separator: " ")
            if name.hasPrefix("*") {
                name.removeFirst()
            }
            result[name] = hash
        }
        return result
    }

    /// 分块读文件算 SHA-256，返回小写十六进制。
    static func sha256(of url: URL) throws -> String {
        try Digests.sha256(ofFile: url)
    }
}

/// 代码签名：判断当前版本是不是用证书签的，以及新版本是不是同一个证书签的。
///
/// 用证书（Developer ID 或者自己生成的签名证书）签名时，程序的「指定要求」（designated requirement）
/// 里写的是证书，每个版本都一样，所以新版本必须满足当前版本的指定要求，别人重新签过名的包不会被装上。
/// 本地签名（ad-hoc）的版本指定要求是这个版本的哈希，没法用来认新版本，只检查签名是否完整。
enum CodeSignature {
    /// 当前运行的 Pop 是不是本地签名（ad-hoc，没有证书）
    static let isAdHoc: Bool = {
        guard let code = staticCode(Bundle.main.bundleURL) else { return true }
        return certificates(of: code).isEmpty
    }()

    /// 签名用的证书名字（比如「Developer ID Application: …」）；本地签名时是 nil
    static let signerName: String? = {
        guard let code = staticCode(Bundle.main.bundleURL),
              let leaf = certificates(of: code).first else { return nil }
        return SecCertificateCopySubjectSummary(leaf) as String?
    }()

    /// 当前版本的指定要求；本地签名时是 nil（不做「同一个证书」的检查）
    static let currentRequirement: SecRequirement? = {
        guard !isAdHoc, let code = staticCode(Bundle.main.bundleURL) else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }()

    /// 当前 Pop 签名证书的 SHA-1（十六进制）；本地签名时是 nil
    static let currentLeafCertificateHash: String? = {
        guard let code = staticCode(Bundle.main.bundleURL), let leaf = certificates(of: code).first else { return nil }
        let data = SecCertificateCopyData(leaf) as Data
        return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }()

    /// 插件包可以装载：签名完整（每个架构都查）；当前 Pop 是用证书签的话，插件包也必须是同一张证书签的。
    /// 本地签名（ad-hoc）的 Pop 只检查插件包的签名完整。
    static func isTrustedPlugin(_ url: URL) -> Bool {
        guard let code = staticCode(url) else { return false }
        var requirement: SecRequirement?
        if let leaf = currentLeafCertificateHash {
            guard SecRequirementCreateWithString("certificate leaf = H\"\(leaf)\"" as CFString, [], &requirement) == errSecSuccess else {
                return false
            }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// url 处的程序签名完整（每个架构都查），并且满足 requirement。
    static func satisfies(_ url: URL, requirement: SecRequirement) -> Bool {
        guard let code = staticCode(url) else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    private static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess else { return nil }
        return code
    }

    private static func certificates(of code: SecStaticCode) -> [SecCertificate] {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { return [] }
        return (values[kSecCodeInfoCertificates as String] as? [SecCertificate]) ?? []
    }
}

/// 系统的「App Translocation」：带隔离标记、又没在访达里挪过位置的程序（比如在下载文件夹里直接打开的），
/// 会从一个只读的临时位置运行。用 Security 框架的函数判断，并找回它原来的位置。
enum Translocation {
    private typealias IsTranslocatedURL = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> UInt8
    private typealias CreateOriginalPathForURL = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    private static let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY)

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        guard let handle else { return nil }
        return dlsym(handle, name)
    }

    static func isTranslocated(_ url: URL) -> Bool {
        if url.path(percentEncoded: false).contains("/AppTranslocation/") {
            return true
        }
        guard let pointer = symbol("SecTranslocateIsTranslocatedURL") else { return false }
        let function = unsafeBitCast(pointer, to: IsTranslocatedURL.self)
        var translocated = false
        _ = function(url as CFURL, &translocated, nil)
        return translocated
    }

    /// 被搬走之前的位置，例如 ~/Downloads/Pop.app。
    static func originalURL(of url: URL) -> URL? {
        guard let pointer = symbol("SecTranslocateCreateOriginalPathForURL") else { return nil }
        let function = unsafeBitCast(pointer, to: CreateOriginalPathForURL.self)
        guard let original = function(url as CFURL, nil)?.takeRetainedValue() else { return nil }
        return (original as URL).standardizedFileURL
    }
}

/// 更新装到哪里。
struct InstallPlan: Equatable {
    /// 新版本放在这里，也从这里重新打开
    var target: URL
    /// 装好后移到废纸篓的旧程序（从下载文件夹这类地方搬进「应用程序」时）
    var trashAfter: URL?
    /// 从临时位置搬进「应用程序」，而不是原地替换
    var relocating: Bool

    /// 按路径比较：同一个 .app 的 URL 可能带或不带结尾的 /
    static func == (a: InstallPlan, b: InstallPlan) -> Bool {
        a.target.standardizedFileURL.path == b.target.standardizedFileURL.path
            && a.trashAfter?.standardizedFileURL.path == b.trashAfter?.standardizedFileURL.path
            && a.relocating == b.relocating
    }
}

/// 平时原地替换；从只读的临时位置运行时（系统搬走了、或者在只读的磁盘上），装进「应用程序」。
enum InstallLocation {
    static let appName = "Pop.app"

    static var applicationsFolders: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    static func current(bundle: URL = Bundle.main.bundleURL) -> InstallPlan? {
        let translocated = Translocation.isTranslocated(bundle)
        let original = translocated ? Translocation.originalURL(of: bundle) : nil
        let readOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return plan(bundle: bundle, translocated: translocated, original: original, readOnly: readOnly,
                    folders: applicationsFolders, canWrite: canWrite)
    }

    /// 纯逻辑，便于测试。folders 按优先顺序，canWrite 判断能不能不用管理员密码写进去。
    static func plan(bundle: URL, translocated: Bool, original: URL?, readOnly: Bool, folders: [URL],
                     canWrite: (URL) -> Bool) -> InstallPlan? {
        guard bundle.pathExtension == "app" else { return nil }
        guard translocated || readOnly else {
            return InstallPlan(target: bundle, trashAfter: nil, relocating: false)
        }
        if let original {
            let parent = original.deletingLastPathComponent().standardizedFileURL.path
            if folders.contains(where: { $0.standardizedFileURL.path == parent }) {
                // 本来就在「应用程序」里，只是带着隔离标记被系统搬到临时位置运行：原地替换
                return InstallPlan(target: original, trashAfter: nil, relocating: false)
            }
        }
        guard let first = folders.first else { return nil }
        let folder = folders.first(where: canWrite) ?? first
        let target = folder.appendingPathComponent(appName, isDirectory: true).standardizedFileURL
        let trash = original.flatMap { $0.standardizedFileURL.path == target.path ? nil : $0 }
        return InstallPlan(target: target, trashAfter: trash, relocating: true)
    }

    /// 不用管理员密码能不能写：文件夹存在时看它本身，不存在时看能不能建出来。
    static func canWrite(_ folder: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue && fileManager.isWritableFile(atPath: folder.path)
        }
        return fileManager.isWritableFile(atPath: folder.deletingLastPathComponent().path)
    }

    static func displayName(of folder: URL) -> String {
        let path = folder.standardizedFileURL.path
        if path == "/Applications" { return String(localized: "「应用程序」") }
        if path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").standardizedFileURL.path {
            return String(localized: "个人的「应用程序」（~/Applications）")
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}

/// 下载、校验、解压、替换、重新启动。除了 relaunch 都是异步的，不阻塞界面。
enum UpdateInstaller {
    /// 经系统代理设置下载到 destination，progress 收到 0…1 的进度（总大小未知时是 nil）。
    static func download(_ url: URL, expectedSize: Int?, to destination: URL,
                         progress: @escaping @Sendable (Double?) -> Void) async throws {
        let delegate = DownloadDelegate(destination: destination, expectedSize: expectedSize, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        // 30 秒没有任何数据才算超时；整个下载最长一小时
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: url)
        request.setValue(UpdateChecker.userAgent, forHTTPHeaderField: "User-Agent")
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                delegate.completion = { result in continuation.resume(with: result) }
                delegate.start(session.downloadTask(with: request))
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    /// 下载校验文件，比对压缩包的 SHA-256。
    static func verify(archive: URL, checksumsURL: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: checksumsURL)
        request.setValue(UpdateChecker.userAgent, forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdateError.server(http.statusCode)
        }
        let expected = Checksums.parse(String(decoding: data, as: UTF8.self))
        guard let hash = expected[archive.lastPathComponent] else { throw UpdateError.checksumsMissing }
        let archiveURL = archive
        let actual = try await runInBackground { () -> Result<String, Error> in
            Result { try Checksums.sha256(of: archiveURL) }
        }.get()
        guard actual == hash else { throw UpdateError.checksumMismatch }
    }

    /// 解压到 directory，返回里面的 .app。
    static func extract(archive: URL, to directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let result = try await run("/usr/bin/ditto", ["-x", "-k", archive.path(percentEncoded: false), directory.path(percentEncoded: false)], timeout: 120)
        guard result.status == 0, !result.timedOut else { throw UpdateError.extract(message(result)) }
        let items = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let app = items.first(where: { $0.pathExtension == "app" }) else { throw UpdateError.appNotFound }
        // 自己下载并校验过的更新，去掉隔离标记，否则换上去之后系统会再拦一次，还会被搬到临时位置运行
        _ = try? await run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path(percentEncoded: false)], timeout: 30)
        return app
    }

    /// 确认解压出来的确实是对应版本的 Pop，签名完整；当前版本是用证书签的时，新版本也必须是同一个证书签的。
    static func validate(app: URL, expectedVersion: String, requirement: SecRequirement? = CodeSignature.currentRequirement) async throws {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw UpdateError.wrongApp(String(localized: "读不到 Info.plist"))
        }
        let identifier = plist["CFBundleIdentifier"] as? String ?? ""
        if let ours = Bundle.main.bundleIdentifier, identifier != ours {
            throw UpdateError.wrongApp(String(localized: "Bundle ID 是 \(identifier)"))
        }
        let version = plist["CFBundleShortVersionString"] as? String ?? ""
        guard version == expectedVersion else {
            throw UpdateError.wrongApp(String(localized: "版本是 \(version)，不是 \(expectedVersion)"))
        }
        let result = try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path(percentEncoded: false)], timeout: 120)
        guard result.status == 0, !result.timedOut else { throw UpdateError.wrongApp(String(localized: "签名校验失败：\(message(result))")) }
        if let requirement, !CodeSignature.satisfies(app, requirement: requirement) {
            throw UpdateError.wrongSigner
        }
    }

    /// 把 newApp 放到 target：先挪到同一个文件夹里的隐藏名字，旧的挪开，再改名，失败就换回去。
    /// target 所在文件夹没有写权限（标准账户装在「应用程序」里）时，用系统的授权对话框以管理员身份做同样的事。
    static func install(newApp: URL, replacing target: URL) async throws {
        let parent = target.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".\(target.lastPathComponent).update")
        let backup = parent.appendingPathComponent(".\(target.lastPathComponent).previous")
        do {
            try swap(newApp: newApp, target: target, staged: staged, backup: backup)
        } catch let error as NSError where isBlockedBySystem(error) {
            throw UpdateError.appManagement
        } catch let error as NSError where needsAdmin(error) {
            let source = FileManager.default.fileExists(atPath: staged.path) ? staged : newApp
            try await swapPrivileged(source: source, target: target, staged: staged, backup: backup)
        } catch {
            throw UpdateError.install(error.localizedDescription)
        }
    }

    private static func swap(newApp: URL, target: URL, staged: URL, backup: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fileManager.removeItem(at: staged)
        try? fileManager.removeItem(at: backup)
        try fileManager.moveItem(at: newApp, to: staged)
        let hadTarget = fileManager.fileExists(atPath: target.path)
        if hadTarget {
            try fileManager.moveItem(at: target, to: backup)
        }
        do {
            try fileManager.moveItem(at: staged, to: target)
        } catch {
            if hadTarget {
                try? fileManager.moveItem(at: backup, to: target)
            }
            throw error
        }
        if hadTarget {
            try? fileManager.removeItem(at: backup)
        }
    }

    private static func swapPrivileged(source: URL, target: URL, staged: URL, backup: URL) async throws {
        let (s, t, b) = (shellQuote(staged.path), shellQuote(target.path), shellQuote(backup.path))
        let script = "rm -rf \(s) \(b) && mkdir -p \(shellQuote(target.deletingLastPathComponent().path)) && mv \(shellQuote(source.path)) \(s)"
            + " && { [ ! -e \(t) ] || mv \(t) \(b); }"
            + " && { mv \(s) \(t) || { [ ! -e \(b) ] || mv \(b) \(t); exit 1; }; }"
            + " && rm -rf \(b)"
        let appleScript = "do shell script " + appleScriptString(script) + " with administrator privileges"
        let result = try await run("/usr/bin/osascript", ["-e", appleScript], timeout: 300)
        guard result.status == 0, !result.timedOut else {
            let text = message(result)
            if text.contains("-128") {
                throw UpdateError.cancelledByUser
            }
            if text.localizedCaseInsensitiveContains("Operation not permitted") {
                throw UpdateError.appManagement
            }
            throw UpdateError.install(text)
        }
    }

    /// 等当前进程退出后再打开新程序：起一个独立的 sh 等着，Pop 自己退出时它不受影响。
    static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = "n=0; while /bin/kill -0 \(pid) 2>/dev/null && [ $n -lt 300 ]; do /bin/sleep 0.2; n=$((n+1)); done; /usr/bin/open \(shellQuote(app.path))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            UpdateLog.info("启动重新打开程序的辅助进程失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 小工具

    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async throws -> ProcessRunner.Output {
        switch await ProcessRunner.run(URL(fileURLWithPath: path), arguments: arguments, stdin: nil, environment: [:], timeout: timeout) {
        case .success(let output):
            return output
        case .failure(let error):
            throw UpdateError.install(error.message)
        }
    }

    private static func message(_ output: ProcessRunner.Output) -> String {
        if output.timedOut { return String(localized: "超时") }
        let text = (output.stderr + "\n" + output.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "退出码 \(Int(output.status))") : String(text.prefix(300))
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 错误里的 POSIX 错误码（FileManager 的错误通常包着一层）
    static func posixCode(_ error: NSError) -> Int? {
        if error.domain == NSPOSIXErrorDomain {
            return error.code
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return posixCode(underlying)
        }
        return nil
    }

    /// 没有写权限（EACCES）：管理员身份可以做
    static func needsAdmin(_ error: NSError) -> Bool {
        if let code = posixCode(error) {
            return code == Int(EACCES)
        }
        return error.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(error.code)
    }

    /// 系统保护（EPERM，比如「App 管理」权限）：管理员身份也做不了
    static func isBlockedBySystem(_ error: NSError) -> Bool {
        posixCode(error) == Int(EPERM)
    }
}

/// 把 URLSession 的下载回调接到 async 调用上，顺便报告进度。
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let destination: URL
    let expectedSize: Int?
    let progress: @Sendable (Double?) -> Void
    private let lock = NSLock()
    private var pending: ((Result<Void, Error>) -> Void)?
    private var task: URLSessionTask?
    private var cancelled = false

    init(destination: URL, expectedSize: Int?, progress: @escaping @Sendable (Double?) -> Void) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.progress = progress
    }

    var completion: ((Result<Void, Error>) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return pending
        }
        set {
            lock.lock()
            pending = newValue
            lock.unlock()
        }
    }

    /// 开始下载；已经取消了就直接结束（取消可能发生在任务建好之前）。
    func start(_ task: URLSessionTask) {
        lock.lock()
        let cancelled = self.cancelled
        if !cancelled {
            self.task = task
        }
        lock.unlock()
        if cancelled {
            task.cancel()
            finish(.failure(CancellationError()))
        } else {
            task.resume()
        }
    }

    /// 取消下载：之后 didCompleteWithError 会收到 cancelled，转成 CancellationError。
    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let handler = pending
        pending = nil
        lock.unlock()
        handler?(result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        var total = totalBytesExpectedToWrite
        if total <= 0, let expectedSize, expectedSize > 0 {
            total = Int64(expectedSize)
        }
        progress(total > 0 ? min(1, Double(totalBytesWritten) / Double(total)) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(UpdateError.server(http.statusCode)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else {
            // 成功时 didFinishDownloadingTo 已经先回调过了，这里什么都不会发生
            finish(.failure(UpdateError.badResponse))
            return
        }
        if (error as? URLError)?.code == .cancelled {
            finish(.failure(CancellationError()))
        } else {
            finish(.failure(error))
        }
    }
}
