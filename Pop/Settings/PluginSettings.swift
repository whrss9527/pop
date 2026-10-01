import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 功能（插件）

struct PluginsSettingsView: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var pluginStore: PluginStore
    let catalog: [PluginInfo]
    /// 打开插件库
    @Binding var showsLibrary: Bool
    @State var editing: PluginDraft? = nil
    @State var errorMessage: String? = nil
    /// 搜索内置功能
    @State private var query = ""

    var body: some View {
        Form {
            Section {
                // 不显示标签：表单里的标签会占掉左半边，框里反而是空的
                TextField("搜索插件和内置功能", text: $query, prompt: Text("搜索插件和内置功能，支持拼音首字母"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }

            // 插件包：要用时装上，不用了卸载
            PluginPackagesSection(query: query)

            Section {
                if pluginStore.manifests.isEmpty {
                    Text("还没有自己的插件。可以到「插件库」里挑现成的装上，也可以从模板新建：用网址模板接入任何网站的搜索，用 Shell 或 JavaScript 脚本处理选中的文字，或者交给快捷指令。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(pluginStore.manifests) { manifest in
                    UserPluginRow(manifest: manifest,
                                  installed: installedBinding(for: manifest.id),
                                  onEdit: { editing = PluginDraft(manifest: manifest, isNew: false) },
                                  onCopyLink: { copyLink(manifest.id) },
                                  onExport: { export(manifest) },
                                  onReveal: { reveal(manifest) },
                                  onDelete: { delete(manifest) })
                }
                ForEach(pluginStore.loadErrors.keys.sorted(), id: \.self) { fileName in
                    Label("\(fileName)：\(pluginStore.loadErrors[fileName] ?? "")", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
                HStack {
                    Button("插件库…") {
                        showsLibrary = true
                    }
                    Menu("新建插件") {
                        ForEach(PluginManifest.templates) { template in
                            Button(template.title) {
                                editing = PluginDraft(manifest: template.manifest, isNew: true)
                            }
                        }
                    }
                    .fixedSize()
                    Button("导入…", action: importPlugins)
                    Spacer()
                    Button("打开插件文件夹") {
                        NSWorkspace.shared.open(pluginStore.directory)
                    }
                }
            } header: {
                Text("我的插件")
            } footer: {
                Text("每个插件是插件文件夹里的一个 JSON 文件，可以直接编辑、拷给别人；打开 iCloud 同步后会同步到你的其他 Mac。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 插件包提供的功能在上面的「插件」里装上、卸载，这里只列 Pop 自带的
            let builtins = catalog.filter { $0.source == .builtin && !PluginCatalog.functionIDs.contains($0.id) && matchesQuery($0) }
            if builtins.isEmpty {
                Section {
                    Text("没有匹配的内置功能")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(BuiltinCategory.allCases) { category in
                let members = builtins.filter { BuiltinCategory.of($0.id) == category }
                if !members.isEmpty {
                    Section {
                        ForEach(members) { info in
                            Toggle(isOn: installedBinding(for: info.id)) {
                                HStack(spacing: 10) {
                                    Image(systemName: info.symbol)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(info.name)
                                        Text(info.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .contextMenu {
                                Button("拷贝链接") { copyLink(info.id) }
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            if category == BuiltinCategory.allCases.first {
                                Text("关掉的功能会从圆盘上移除，也不会再被直达规则调用。打开后到「圆盘」里拖到想要的位置，或者在圆盘的「全部功能」里找到它。右键一个功能可以拷贝它的 pop:// 链接，给快捷指令和脚本用。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("内置功能 · \(category.title)")
                        }
                    }
                }
            }

            Section("搜索") {
                Picker("搜索引擎", selection: store.binding(\.searchEngine)) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showsLibrary) {
            PluginLibraryView(store: store, pluginStore: pluginStore, onClose: { showsLibrary = false })
        }
        .sheet(item: $editing) { draft in
            PluginEditorView(draft: draft, ai: store.settings.ai, onSave: { manifest in
                save(manifest, isNew: draft.isNew)
            }, onCancel: {
                editing = nil
            })
        }
        .alert("操作没有完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func matchesQuery(_ info: PluginInfo) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return SearchText.matches(trimmed, keys: SearchText.keys(for: info.name) + [info.summary.lowercased()])
    }

    private func installedBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { store.settings.isInstalled(id) },
            set: { installed in store.update { $0.setInstalled(id, installed) } }
        )
    }

    /// 保存成功返回 nil，否则返回错误信息（显示在编辑器里）。
    private func save(_ manifest: PluginManifest, isNew: Bool) -> String? {
        do {
            let saved = try pluginStore.save(manifest)
            if isNew {
                store.update { $0.setInstalled(saved.id, true) }
            }
            editing = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func importPlugins() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var failures: [String] = []
        for url in panel.urls {
            do {
                let imported = try pluginStore.importFile(at: url)
                store.update { $0.setInstalled(imported.id, true) }
            } catch {
                failures.append(String(localized: "\(url.lastPathComponent)：\(error.localizedDescription)"))
            }
        }
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    private func export(_ manifest: PluginManifest) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(manifest.name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pluginStore.export(manifest, to: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 执行这个功能的 pop:// 链接，给快捷指令和脚本用
    private func copyLink(_ id: String) {
        PasteboardWriter.copy(PopLink.runURL(id).absoluteString)
    }

    private func reveal(_ manifest: PluginManifest) {
        if let url = pluginStore.fileURL(for: manifest.id) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(pluginStore.directory)
        }
    }

    private func delete(_ manifest: PluginManifest) {
        let alert = NSAlert()
        alert.messageText = String(localized: "删除插件「\(manifest.displayName)」？")
        alert.informativeText = String(localized: "插件文件会被删除；打开了 iCloud 同步的话，其他 Mac 上的这个插件也会删除。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "删除"))
        alert.addButton(withTitle: String(localized: "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        pluginStore.delete(id: manifest.id)
        store.update { $0.setInstalled(manifest.id, false) }
    }
}

struct UserPluginRow: View {
    let manifest: PluginManifest
    @Binding var installed: Bool
    let onEdit: () -> Void
    let onCopyLink: () -> Void
    let onExport: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("启用", isOn: $installed)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Image(systemName: manifest.symbol)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(manifest.displayName)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("编辑", action: onEdit)
                .controlSize(.small)
            Menu {
                Button("拷贝链接", action: onCopyLink)
                Button("导出…", action: onExport)
                Button("在访达中显示", action: onReveal)
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var subtitle: String {
        let detail = manifest.displaySummary.isEmpty ? manifest.match.kinds.map(\.title).joinedAsList() : manifest.displaySummary
        return detail.isEmpty ? manifest.action.type.title : "\(manifest.action.type.title) · \(detail)"
    }
}

struct PluginDraft: Identifiable {
    let id = UUID()
    var manifest: PluginManifest
    var isNew: Bool
}

// MARK: - 插件编辑器

struct PluginEditorView: View {
    private let isNew: Bool
    /// 试运行 AI 指令用的接口设置
    private let ai: AISettings
    private let onSave: (PluginManifest) -> String?
    private let onCancel: () -> Void

    @State private var manifest: PluginManifest
    @State private var error: String? = nil
    @State private var testInput = "Hello Pop"
    @State private var testResult: String? = nil
    @State private var testFailed = false
    @State private var testMatches = true
    @State private var isTesting = false
    @State private var shortcuts: [String] = []

    /// 编辑器里可以勾选的内容类型
    private static let selectableKinds: [ContentKind] = [
        .text, .foreignText, .chineseText, .word, .url, .email, .json, .number,
        .color, .dateTime, .timestamp, .math, .measurement, .files, .imageFile, .image,
    ]

    init(draft: PluginDraft, ai: AISettings, onSave: @escaping (PluginManifest) -> String?, onCancel: @escaping () -> Void) {
        isNew = draft.isNew
        self.ai = ai
        self.onSave = onSave
        self.onCancel = onCancel
        _manifest = State(initialValue: draft.manifest)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $manifest.name)
                    HStack {
                        TextField("图标", text: $manifest.symbol, prompt: Text("SF Symbol 名称，比如 globe"))
                        Image(systemName: symbolPreview)
                            .frame(width: 24)
                    }
                    TextField("说明", text: $manifest.summary, prompt: Text("可选"))
                }

                Section {
                    Picker("类型", selection: $manifest.action.type) {
                        ForEach(PluginManifest.Action.Kind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    actionEditor
                    if manifest.action.type != .url {
                        Picker("结果", selection: $manifest.output) {
                            ForEach(PluginManifest.Output.allCases) { output in
                                Text(output.title).tag(output)
                            }
                        }
                    }
                    if manifest.action.type != .url, manifest.action.type != .ai {
                        Stepper(value: $manifest.action.timeout, in: PluginManifest.Action.timeoutRange, step: 5) {
                            Text("最长运行 \(Int(manifest.action.timeout)) 秒")
                        }
                    }
                } header: {
                    Text("动作")
                } footer: {
                    Text(actionHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4), alignment: .leading, spacing: 6) {
                        ForEach(Self.selectableKinds, id: \.self) { kind in
                            Toggle(kind.title, isOn: kindBinding(kind))
                                .toggleStyle(.checkbox)
                        }
                    }
                    TextField("正则", text: patternBinding, prompt: Text("可选，比如 ^[A-Z]{2,}$"))
                } header: {
                    Text("什么时候可用")
                } footer: {
                    Text("勾选能处理的内容类型；一个都不勾表示随时可用（不需要选中内容）。填了正则的话，选中的文字还要能匹配它。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("试运行") {
                    TextField("输入", text: $testInput, axis: .vertical)
                        .lineLimit(1...4)
                    HStack {
                        Button("运行", action: runTest)
                            .disabled(isTesting)
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        if !testMatches {
                            Text("这段内容不满足「什么时候可用」，在圆盘里不会出现")
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                        }
                    }
                    if let testResult {
                        Text(testResult)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(testFailed ? Color.red : Color.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? String(localized: "添加") : String(localized: "保存"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 580, height: 640)
        .task(id: manifest.action.type) {
            if manifest.action.type == .shortcut, shortcuts.isEmpty {
                shortcuts = await ShortcutsCatalog.names()
            }
        }
    }

    @ViewBuilder
    private var actionEditor: some View {
        switch manifest.action.type {
        case .url:
            TextField("网址", text: $manifest.action.template, prompt: Text("https://example.com/search?q={text}"))
        case .shell, .javascript:
            TextEditor(text: $manifest.action.script)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 150)
        case .ai:
            TextEditor(text: $manifest.action.prompt)
                .font(.body)
                .frame(height: 120)
        case .shortcut:
            HStack {
                TextField("快捷指令", text: $manifest.action.shortcut, prompt: Text("快捷指令的名称"))
                if !shortcuts.isEmpty {
                    Menu("选择") {
                        ForEach(shortcuts, id: \.self) { name in
                            Button(name) {
                                manifest.action.shortcut = name
                            }
                        }
                    }
                    .fixedSize()
                }
            }
        }
    }

    private var actionHelp: String {
        switch manifest.action.type {
        case .url:
            return String(localized: "{text} 会换成编码后的选中文字，{raw} 换成原文。可以用任何网址，也可以用 App 的链接（比如 maps://?q={text}）。")
        case .shell:
            return String(localized: "用 zsh 运行。选中的文字从标准输入传入，也可以读环境变量 $POP_TEXT；选中文件时 $POP_FILES 是每行一个路径。标准输出就是结果，退出码不为 0 时显示错误输出。")
        case .javascript:
            return String(localized: "定义 function run(input, files) 并返回结果（返回对象会自动转成 JSON），也可以直接写一个表达式。脚本在隔离的环境里运行，不能访问网络和文件。")
        case .shortcut:
            return String(localized: "选中的文字作为快捷指令的输入，快捷指令的输出就是结果。第一次运行时系统可能会请求权限。")
        case .ai:
            return String(localized: "指令和选中的文字一起发给「设置 → AI」里填写的服务，{text} 换成选中的文字（没写的话文字接在指令后面）。结果选「显示结果卡片」时一边生成一边显示。")
        }
    }

    private var symbolPreview: String {
        NSImage(systemSymbolName: manifest.symbol, accessibilityDescription: nil) == nil ? "questionmark.square.dashed" : manifest.symbol
    }

    private var patternBinding: Binding<String> {
        Binding(
            get: { manifest.match.pattern ?? "" },
            set: { manifest.match.pattern = $0.isEmpty ? nil : $0 }
        )
    }

    private func kindBinding(_ kind: ContentKind) -> Binding<Bool> {
        Binding(
            get: { manifest.match.kinds.contains(kind) },
            set: { enabled in
                if enabled {
                    if !manifest.match.kinds.contains(kind) {
                        manifest.match.kinds.append(kind)
                    }
                } else {
                    manifest.match.kinds.removeAll { $0 == kind }
                }
            }
        )
    }

    private func save() {
        if let problem = manifest.validationError() {
            error = problem
            return
        }
        error = onSave(manifest)
    }

    private func runTest() {
        let normalized = manifest.normalized()
        let content = ContentClassifier.classify(.text(testInput))
        testMatches = ManifestPlugin(manifest: normalized).info.canHandle(content)
        if let problem = normalized.validationError() {
            testFailed = true
            testResult = problem
            return
        }
        isTesting = true
        testResult = nil
        let input = ManifestRunner.Input(content)
        Task {
            let result = await ManifestRunner.execute(normalized.action, input: input, ai: ai)
            isTesting = false
            switch result {
            case .success(let output):
                testFailed = false
                testResult = output.isEmpty ? String(localized: "（没有输出）") : output
            case .failure(let failure):
                testFailed = true
                testResult = failure.message
            }
        }
    }
}

/// 列出本机的快捷指令，编辑器里方便选择。
enum ShortcutsCatalog {
    static func names() async -> [String] {
        let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/shortcuts"), arguments: ["list"],
                                             stdin: nil, environment: [:], timeout: 10)
        guard case .success(let output) = result, output.status == 0 else { return [] }
        return output.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
