import AppKit
import JavaScriptCore

/// 由 manifest 描述的用户插件。
struct ManifestPlugin: PopPlugin, Equatable {
    let manifest: PluginManifest

    var info: PluginInfo {
        PluginInfo(id: manifest.id,
                   name: manifest.displayName.isEmpty ? String(localized: "未命名插件") : manifest.displayName,
                   symbol: manifest.symbol,
                   summary: manifest.displaySummary.isEmpty ? manifest.action.type.title : manifest.displaySummary,
                   accepts: Set(manifest.match.kinds),
                   pattern: manifest.match.pattern,
                   minLength: manifest.match.minLength,
                   maxLength: manifest.match.maxLength,
                   source: .user)
    }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        await ManifestRunner.run(manifest, content: content, ai: context.settings.ai)
    }
}

struct PluginRunError: Error, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// 执行用户插件：网址模板、Shell 脚本、JavaScript、快捷指令、AI 指令。
enum ManifestRunner {
    /// 交给插件的输入
    struct Input: Equatable {
        /// 选中的文字；选中文件时是每行一个路径
        var text: String
        var files: [String]
        var kinds: [String]

        init(text: String, files: [String] = [], kinds: [String] = []) {
            self.text = text
            self.files = files
            self.kinds = kinds
        }

        init(_ content: ClassifiedContent) {
            let files = content.files.map { $0.path(percentEncoded: false) }
            self.init(text: content.text ?? files.joined(separator: "\n"),
                      files: files,
                      kinds: content.kinds.map(\.rawValue).sorted())
        }
    }

    /// 环境变量有长度上限（和命令行参数共用约 1 MB），太长的文字只从标准输入传。
    static let maxEnvironmentLength = 64_000

    @MainActor
    static func run(_ manifest: PluginManifest, content: ClassifiedContent, ai: AISettings = AISettings()) async -> PluginOutcome {
        let input = Input(content)
        if manifest.action.type == .url {
            guard let url = expandURL(manifest.action.template, input: input) else {
                return .failure(String(localized: "「\(manifest.name)」的网址模板无效"))
            }
            NSWorkspace.shared.open(url)
            return .done(toast: nil)
        }
        if manifest.action.type == .ai, manifest.output == .card {
            // 结果卡片一边生成一边显示
            return .ai(AIRequestSpec(text: input.text, prompt: AIPrompt.expand(manifest.action.prompt, text: input.text),
                                     label: manifest.name))
        }
        switch await execute(manifest.action, input: input, ai: ai) {
        case .success(let output):
            return present(output, manifest: manifest, canReplace: content.text != nil)
        case .failure(let error):
            return .failure(String(localized: "「\(manifest.name)」运行失败：\(error.message)"))
        }
    }

    /// 运行插件并返回输出（去掉末尾换行）。网址插件只返回展开后的网址，不会打开，设置里的「试运行」也用它。
    static func execute(_ action: PluginManifest.Action, input: Input, ai: AISettings? = nil) async -> Result<String, PluginRunError> {
        switch action.type {
        case .url:
            guard let url = expandURL(action.template, input: input) else {
                return .failure(PluginRunError(String(localized: "网址模板无效")))
            }
            return .success(url.absoluteString)
        case .shell:
            let result = await ProcessRunner.run(URL(fileURLWithPath: "/bin/zsh"),
                                                 arguments: ["-c", action.script],
                                                 stdin: input.text,
                                                 environment: environment(for: input),
                                                 timeout: action.timeout)
            return result.flatMap(scriptOutput)
        case .javascript:
            return await JavaScriptRunner.run(action.script, input: input, timeout: action.timeout).map(trimTrailingNewlines)
        case .shortcut:
            return await runShortcut(action.shortcut, input: input, timeout: action.timeout)
        case .ai:
            guard let ai else {
                return .failure(PluginRunError(AIClient.describe(AIClient.Failure.notConfigured)))
            }
            let onDevice = OnDeviceModel.status
            guard AIService.backend(for: ai, onDevice: onDevice) != .unavailable else {
                return .failure(PluginRunError(AIService.unavailableMessage(for: ai, onDevice: onDevice)))
            }
            let messages: [AIClient.Message] = [.system(AIPrompt.system), .user(AIPrompt.expand(action.prompt, text: input.text))]
            do {
                let output = try await AIService.complete(messages, settings: ai, onDevice: onDevice)
                return .success(trimTrailingNewlines(output))
            } catch {
                return .failure(PluginRunError(AIClient.describe(error)))
            }
        }
    }

    @MainActor
    static func present(_ output: String, manifest: PluginManifest, canReplace: Bool) -> PluginOutcome {
        switch manifest.output {
        case .card:
            guard !output.isEmpty else { return .done(toast: String(localized: "「\(manifest.name)」已完成")) }
            return .card(ResultCard(title: manifest.name, body: output, monospaced: true,
                                    copyText: output, replaceText: canReplace ? output : nil))
        case .copy:
            guard !output.isEmpty else { return .failure(String(localized: "「\(manifest.name)」没有输出")) }
            PasteboardWriter.copy(output)
            return .done(toast: String(localized: "已复制结果"))
        case .replace:
            guard canReplace else { return .failure(String(localized: "选中的不是文字，无法替换")) }
            guard !output.isEmpty else { return .failure(String(localized: "「\(manifest.name)」没有输出，原文保持不变")) }
            return .replace(output)
        case .toast:
            let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return .done(toast: firstLine.isEmpty ? String(localized: "已完成") : String(firstLine.prefix(60)))
        case .none:
            return .done(toast: nil)
        }
    }

    /// 展开网址模板：{text} 换成编码后的文字，{raw} 原样替换。
    static func expandURL(_ template: String, input: Input) -> URL? {
        let encoded = input.text.addingPercentEncoding(withAllowedCharacters: .popURLValueAllowed) ?? ""
        let filled = template
            .replacingOccurrences(of: "{text}", with: encoded)
            .replacingOccurrences(of: "{raw}", with: input.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: filled), url.scheme != nil else { return nil }
        return url
    }

    static func environment(for input: Input) -> [String: String] {
        [
            "POP_TEXT": String(input.text.prefix(maxEnvironmentLength)),
            "POP_FILES": input.files.joined(separator: "\n"),
            "POP_KINDS": input.kinds.joined(separator: ","),
        ]
    }

    static func trimTrailingNewlines(_ text: String) -> String {
        var result = text
        while let last = result.last, last.isNewline {
            result.removeLast()
        }
        return result
    }

    private static func scriptOutput(_ output: ProcessRunner.Output) -> Result<String, PluginRunError> {
        if output.timedOut {
            return .failure(PluginRunError(String(localized: "运行超时")))
        }
        guard output.status == 0 else {
            let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(PluginRunError(message.isEmpty ? String(localized: "脚本退出码 \(Int(output.status))") : String(message.prefix(500))))
        }
        return .success(trimTrailingNewlines(output.stdout))
    }

    private static func runShortcut(_ name: String, input: Input, timeout: TimeInterval) async -> Result<String, PluginRunError> {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appending(path: "pop-shortcut-\(UUID().uuidString)", directoryHint: .isDirectory)
        let inputURL = directory.appending(path: "input.txt")
        let outputURL = directory.appending(path: "output.txt")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(input.text.utf8).write(to: inputURL)
        } catch {
            return .failure(PluginRunError(String(localized: "无法准备输入：\(error.localizedDescription)")))
        }
        defer { try? fileManager.removeItem(at: directory) }

        let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/shortcuts"),
                                             arguments: ["run", name,
                                                         "--input-path", inputURL.path(percentEncoded: false),
                                                         "--output-path", outputURL.path(percentEncoded: false),
                                                         "--output-type", "public.plain-text"],
                                             stdin: nil,
                                             environment: [:],
                                             timeout: timeout)
        switch result {
        case .failure(let error):
            return .failure(error)
        case .success(let output):
            if output.timedOut {
                return .failure(PluginRunError(String(localized: "快捷指令运行超时")))
            }
            guard output.status == 0 else {
                let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return .failure(PluginRunError(message.isEmpty ? String(localized: "快捷指令「\(name)」运行失败") : String(message.prefix(500))))
            }
            let text = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? output.stdout
            return .success(trimTrailingNewlines(text))
        }
    }
}

// MARK: - 子进程

/// 运行子进程：标准输入写入文字，收集标准输出和错误输出，超时后结束进程。
enum ProcessRunner {
    struct Output: Equatable {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
    }

    static func run(_ executable: URL, arguments: [String], stdin: String?, environment: [String: String],
                    timeout: TimeInterval) async -> Result<Output, PluginRunError> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(executable, arguments: arguments, stdin: stdin,
                                                       environment: environment, timeout: timeout))
            }
        }
    }

    /// 子进程提前退出时继续写标准输入会收到 SIGPIPE，默认会让整个 App 退出。
    private static let sigpipeIgnored: Void = {
        _ = signal(SIGPIPE, SIG_IGN)
    }()

    static func runSync(_ executable: URL, arguments: [String], stdin: String?, environment: [String: String],
                        timeout: TimeInterval) -> Result<Output, PluginRunError> {
        _ = sigpipeIgnored

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        // 从访达启动的 App 没有 Homebrew 的路径
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe: Pipe? = stdin == nil ? nil : Pipe()
        if let stdinPipe {
            process.standardInput = stdinPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exited.signal()
        }

        do {
            try process.run()
        } catch {
            return .failure(PluginRunError(String(localized: "无法运行 \(executable.lastPathComponent)：\(error.localizedDescription)")))
        }

        let stdoutBox = DataBox()
        let stderrBox = DataBox()
        let readers = DispatchGroup()
        read(stdoutPipe, into: stdoutBox, group: readers)
        read(stderrPipe, into: stderrBox, group: readers)

        if let stdinPipe, let stdin {
            let data = Data(stdin.utf8)
            DispatchQueue.global(qos: .userInitiated).async {
                let handle = stdinPipe.fileHandleForWriting
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
        }
        // 脚本放到后台的子进程可能一直占着输出管道，最多再等一秒
        _ = readers.wait(timeout: .now() + 1)
        let status: Int32 = process.isRunning ? -1 : process.terminationStatus
        return .success(Output(status: status, stdout: stdoutBox.string, stderr: stderrBox.string, timedOut: timedOut))
    }

    private static func read(_ pipe: Pipe, into box: DataBox, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.set(pipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ newValue: Data) {
        lock.lock()
        data = newValue
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

/// 保证 continuation 只恢复一次（正常结束和超时谁先到算谁的）。
final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

// MARK: - JavaScript

/// 在 JavaScriptCore 里运行插件脚本。约定：定义 `function run(input, files)` 并返回结果；
/// 也可以不定义 run，直接写一个表达式（最后一个表达式的值就是结果）。返回对象时自动转成 JSON。
enum JavaScriptRunner {
    static func run(_ source: String, input: ManifestRunner.Input, timeout: TimeInterval) async -> Result<String, PluginRunError> {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                once.resume(runSync(source, input: input, timeout: timeout))
            }
            // 兜底：万一没能设置执行时间上限，也不让调用方一直等下去
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1) {
                once.resume(.failure(PluginRunError(String(localized: "运行超时"))))
            }
        }
    }

    private static let helpers = """
    function __popStringify(value) {
      if (value === undefined || value === null) return '';
      if (typeof value === 'string') return value;
      if (typeof value === 'object') {
        try { return JSON.stringify(value, null, 2); } catch (e) { return String(value); }
      }
      return String(value);
    }
    """

    static func runSync(_ source: String, input: ManifestRunner.Input, timeout: TimeInterval) -> Result<String, PluginRunError> {
        guard let context = JSContext() else {
            return .failure(PluginRunError(String(localized: "无法创建 JavaScript 运行环境")))
        }
        setExecutionTimeLimit(context, seconds: timeout)

        var logs: [String] = []
        let log: @convention(block) () -> Void = {
            let arguments = (JSContext.currentArguments() as? [JSValue]) ?? []
            logs.append(arguments.map { $0.toString() ?? "" }.joined(separator: " "))
        }
        if let console = JSValue(newObjectIn: context) {
            console.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "log" as NSString)
            context.setObject(console, forKeyedSubscript: "console" as NSString)
        }
        context.setObject(input.text, forKeyedSubscript: "input" as NSString)
        context.setObject(input.files, forKeyedSubscript: "files" as NSString)
        _ = context.evaluateScript(helpers)

        let completion = context.evaluateScript(source)
        if let exception = context.exception {
            return .failure(PluginRunError(describe(exception)))
        }

        let value: JSValue?
        if context.evaluateScript("typeof run === 'function'")?.toBool() == true {
            value = context.objectForKeyedSubscript("run")?.call(withArguments: [input.text, input.files])
        } else {
            value = completion
        }
        if let exception = context.exception {
            return .failure(PluginRunError(describe(exception)))
        }

        let argument: JSValue = value ?? JSValue(undefinedIn: context)
        let text = context.objectForKeyedSubscript("__popStringify")?.call(withArguments: [argument])?.toString() ?? ""
        if let exception = context.exception {
            return .failure(PluginRunError(describe(exception)))
        }
        // 没有返回值时，把 console.log 的内容当作结果，方便调试
        if text.isEmpty, !logs.isEmpty {
            return .success(logs.joined(separator: "\n"))
        }
        return .success(text)
    }

    private static func describe(_ exception: JSValue) -> String {
        let message = exception.toString() ?? String(localized: "未知错误")
        if let line = exception.objectForKeyedSubscript("line"), line.isNumber {
            return String(localized: "第 \(Int(line.toInt32())) 行：\(message)")
        }
        return message
    }

    // JavaScriptCore 的公开接口没有执行时间上限，这里动态查找它的 C 函数（找不到就只靠外层超时兜底）。
    private typealias SetTimeLimit = @convention(c) (OpaquePointer?, Double, OpaquePointer?, UnsafeMutableRawPointer?) -> Void

    private static let setTimeLimit: SetTimeLimit? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "JSContextGroupSetExecutionTimeLimit") else { return nil }
        return unsafeBitCast(symbol, to: SetTimeLimit.self)
    }()

    private static func setExecutionTimeLimit(_ context: JSContext, seconds: TimeInterval) {
        guard let setTimeLimit, let global = context.jsGlobalContextRef else { return }
        setTimeLimit(JSContextGetGroup(global), seconds, nil, nil)
    }
}
