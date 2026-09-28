import AppKit
import SwiftUI
import Translation
import UniformTypeIdentifiers

// MARK: - 通用

struct GeneralSettingsView: View {
    @EnvironmentObject private var store: SettingsStore
    @EnvironmentObject private var permissions: PermissionMonitor
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String? = nil

    var body: some View {
        Form {
            Section("快速上手") {
                QuickStartRow(number: 1, title: "授予辅助功能权限",
                              detail: "Pop 要靠它识别长按右键、读取选中的内容，所有处理都在本机完成。")
                QuickStartRow(number: 2, title: "按住右键，不要松开",
                              detail: triggerHint)
                QuickStartRow(number: 3, title: "菜单栏里的 ◎ 就是 Pop",
                              detail: "点它可以打开设置、暂停或退出。菜单栏图标太多时可能被刘海挡住；macOS 26 也可能在「系统设置 → 菜单栏」里把它隐藏了。找不到图标时，再次打开 Pop 应用就会弹出这个窗口。")
            }

            Section("权限") {
                HStack(spacing: 10) {
                    Image(systemName: permissionSymbol)
                        .foregroundStyle(permissionReady ? Color.green : Color.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permissionTitle)
                        Text(permissionDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !permissions.isTrusted {
                        Button("去授权") {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    } else if !permissions.isTriggerRunning {
                        Button("重启 Pop") {
                            AppRelauncher.relaunch()
                        }
                    }
                }
            }

            Section {
                Picker("鼠标", selection: store.binding(\.trigger.mode)) {
                    ForEach(TriggerMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if store.settings.trigger.mode == .longPressRight {
                    LabeledContent("长按时长") {
                        HStack {
                            Slider(value: store.binding(\.trigger.holdDuration), in: TriggerSettings.holdDurationRange, step: 0.05)
                            Text("\(Int((store.settings.trigger.holdDuration * 1000).rounded())) ms")
                                .monospacedDigit()
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                }
                if store.settings.trigger.mode == .modifierRightClick {
                    Picker("修饰键", selection: store.binding(\.trigger.modifier)) {
                        ForEach(TriggerModifier.allCases) { modifier in
                            Text(modifier.title).tag(modifier)
                        }
                    }
                }
                Picker("键盘快捷键", selection: store.binding(\.trigger.hotKey)) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
            } header: {
                Text("唤起方式")
            } footer: {
                Text("长按右键：短按仍然是系统右键菜单，按住超过设定时长才唤起 Pop。按住时往某个方向一划再松开，可以直接执行那一格的功能；在圆心松开则保持圆盘打开，改用点击选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ExcludedAppsView()
            } header: {
                Text("排除的 App")
            } footer: {
                Text("在这些 App 里不响应鼠标唤起，比如依赖右键拖拽的游戏、远程桌面和虚拟机。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("其他") {
                Toggle("登录时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.setEnabled(newValue)
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button("恢复默认设置", role: .destructive) {
                    store.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension GeneralSettingsView {
    private var permissionReady: Bool {
        permissions.isTrusted && permissions.isTriggerRunning
    }

    private var permissionSymbol: String {
        permissionReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    private var permissionTitle: String {
        if !permissions.isTrusted { return "需要辅助功能权限" }
        return permissions.isTriggerRunning ? "已获得辅助功能权限，Pop 已就绪" : "已授权，但鼠标拦截还没生效"
    }

    private var permissionDetail: String {
        if !permissions.isTrusted {
            return "点「去授权」，在「系统设置 → 隐私与安全性 → 辅助功能」里打开 Pop。授权后不用重启，几秒内自动生效。"
        }
        if !permissions.isTriggerRunning {
            return "偶尔刚授权时系统还没放行，点「重启 Pop」即可。"
        }
        return "所有处理都在本机完成。"
    }

    private var triggerHint: String {
        let trigger = store.settings.trigger
        switch trigger.mode {
        case .longPressRight:
            let ms = Int((trigger.holdDuration * 1000).rounded())
            return "选中文字后按住鼠标右键约 \(ms) 毫秒再松开：选中外文会直接翻译，其他情况弹出圆盘。普通点一下右键仍然是系统菜单。"
        case .modifierRightClick:
            return "按住 \(trigger.modifier.title) 再点鼠标右键唤起 Pop。"
        case .middleClick:
            return "点击鼠标中键唤起 Pop。"
        case .disabled:
            return trigger.hotKey == .none ? "鼠标唤起已关闭，可以在下面设置一个键盘快捷键。" : "用键盘快捷键 \(trigger.hotKey.title) 唤起 Pop。"
        }
    }
}

private struct QuickStartRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ExcludedAppsView: View {
    var body: some View {
        BundleIDListView(keyPath: \.trigger.excludedBundleIDs)
    }
}

/// 一组 App（按 Bundle ID 保存），可以添加和移除。
struct BundleIDListView: View {
    @EnvironmentObject var store: SettingsStore
    let keyPath: WritableKeyPath<AppSettings, [String]>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.settings[keyPath: keyPath], id: \.self) { bundleID in
                HStack(spacing: 8) {
                    if let icon = AppInfo.icon(for: bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text(AppInfo.name(for: bundleID))
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.update { $0[keyPath: keyPath].removeAll { $0 == bundleID } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button("添加 App…", action: addApps)
        }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        let bundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        let keyPath = self.keyPath
        store.update { settings in
            for id in bundleIDs where !settings[keyPath: keyPath].contains(id) {
                settings[keyPath: keyPath].append(id)
            }
        }
    }
}

// MARK: - 圆盘布局

struct RingSettingsView: View {
    @EnvironmentObject var store: SettingsStore
    let catalog: [PluginInfo]

    private var installed: [PluginInfo] {
        catalog.filter { store.settings.isInstalled($0.id) }
    }

    private var slotCount: Binding<Int> {
        Binding(
            get: { store.settings.ring.slotCount },
            set: { count in store.update { $0.ring.setSlotCount(count) } }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("已安装的功能")
                    .font(.headline)
                Text("拖到右边的格子上放置；拖到已占用的格子会互换位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List(installed) { info in
                    PluginRow(info: info, slotIndex: store.settings.ring.index(of: info.id))
                        .draggable(info.id)
                }
                .listStyle(.bordered)
            }
            .frame(width: 250)

            VStack(spacing: 14) {
                RingEditorCanvas(layout: store.settings.ring, catalog: catalog, installed: installed) { pluginID, index in
                    store.update { $0.ring.place(pluginID, at: index) }
                }
                Picker("格子数", selection: slotCount) {
                    ForEach(RingLayout.allowedSlotCounts, id: \.self) { count in
                        Text("\(count) 格").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                HStack {
                    Text("格子上点右键可以直接选择功能或清空。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("恢复默认布局") {
                        store.update { $0.ring = .default }
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(20)
    }
}

struct PluginRow: View {
    let info: PluginInfo
    let slotIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: info.symbol)
                .frame(width: 22)
            Text(info.name)
            Spacer()
            Text(slotIndex.map { "第 \($0 + 1) 格" } ?? "未放置")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct RingEditorCanvas: View {
    let layout: RingLayout
    let catalog: [PluginInfo]
    let installed: [PluginInfo]
    let onPlace: (String?, Int) -> Void

    @State var targetedSlot: Int? = nil

    var body: some View {
        let geometry = RingGeometry(slotCount: max(layout.slotCount, 1), innerRadius: 46, outerRadius: 158)
        let size = geometry.diameter
        ZStack {
            Circle()
                .fill(Color.secondary.opacity(0.07))
            Circle()
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            Circle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: geometry.innerRadius * 2, height: geometry.innerRadius * 2)
            Text("0 号格在正上方\n顺时针排列")
                .font(.system(size: 9))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            ForEach(Array(layout.slots.enumerated()), id: \.offset) { index, pluginID in
                let offset = geometry.slotCenterOffset(index)
                slot(index: index, pluginID: pluginID)
                    .position(x: size / 2 + offset.dx, y: size / 2 - offset.dy)
            }
        }
        .frame(width: size, height: size)
    }

    private func slot(index: Int, pluginID: String?) -> some View {
        let info = pluginID.flatMap { id in catalog.first(where: { $0.id == id }) }
        let isTargeted = targetedSlot == index
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isTargeted ? Color.accentColor.opacity(0.25) : Color(nsColor: .controlBackgroundColor))
                Circle()
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isTargeted ? 2 : 1)
                if let info {
                    Image(systemName: info.symbol)
                        .font(.system(size: 18))
                } else {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48, height: 48)
            Text(info?.name ?? "空")
                .font(.caption2)
                .foregroundStyle(info == nil ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
        .frame(width: 76)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first else { return false }
            onPlace(id, index)
            return true
        } isTargeted: { targeted in
            if targeted {
                targetedSlot = index
            } else if targetedSlot == index {
                targetedSlot = nil
            }
        }
        .contextMenu {
            ForEach(installed) { plugin in
                Button(plugin.name) { onPlace(plugin.id, index) }
            }
            Divider()
            Button("清空这一格") { onPlace(nil, index) }
        }
        .help(info?.summary ?? "空格子")
    }
}

// MARK: - 直达规则

struct RulesSettingsView: View {
    @EnvironmentObject var store: SettingsStore
    let catalog: [PluginInfo]

    var body: some View {
        Form {
            Section {
                ForEach(store.settings.rules) { rule in
                    RuleRow(rule: rule, candidates: candidates(for: rule.condition)) { updated in
                        store.update { settings in
                            if let index = settings.rules.firstIndex(where: { $0.condition == updated.condition }) {
                                settings.rules[index] = updated
                            }
                        }
                    }
                }
            } header: {
                Text("选中的内容满足条件时，不弹圆盘，直接执行对应功能")
            } footer: {
                Text("从上到下依次匹配。没有命中任何规则、或者什么都没选中时，弹出圆盘。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func candidates(for condition: RuleCondition) -> [PluginInfo] {
        catalog.filter { info in
            store.settings.isInstalled(info.id) && !info.accepts.isEmpty && !info.accepts.isDisjoint(with: condition.impliedKinds)
        }
    }
}

struct RuleRow: View {
    let rule: DirectRule
    let candidates: [PluginInfo]
    let onChange: (DirectRule) -> Void

    var body: some View {
        HStack {
            Toggle(rule.condition.title, isOn: Binding(
                get: { rule.enabled },
                set: { enabled in
                    var updated = rule
                    updated.enabled = enabled
                    onChange(updated)
                }
            ))
            Spacer()
            Picker("", selection: Binding(
                get: { rule.pluginID ?? "" },
                set: { id in
                    var updated = rule
                    updated.pluginID = id.isEmpty ? nil : id
                    onChange(updated)
                }
            )) {
                Text("（弹出圆盘）").tag("")
                ForEach(candidates) { info in
                    Text(info.name).tag(info.id)
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .disabled(!rule.enabled)
        }
    }
}

extension RuleCondition {
    /// 满足这个条件的内容一定具备的特征（比如「外文」一定也是「文本」）
    var impliedKinds: Set<ContentKind> {
        switch self {
        case .files: return [.files]
        case .image: return [.image]
        case .anyText: return [.text]
        default: return [.text, kind]
        }
    }
}

// MARK: - 翻译

struct TranslationSettingsView: View {
    @EnvironmentObject private var store: SettingsStore

    var body: some View {
        Form {
            Section("目标语言") {
                Picker("外文译为", selection: store.binding(\.translation.foreignTarget)) {
                    ForEach(LanguageOption.translationTargets) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                Picker("中文译为", selection: store.binding(\.translation.chineseTarget)) {
                    ForEach(LanguageOption.translationTargets) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }
            Section {
                LanguagePackView()
            } header: {
                Text("离线语言包")
            } footer: {
                Text("Pop 使用 macOS 自带的离线翻译：不联网、不收费、原文不离开这台 Mac。第一次翻译某个语言组合前，需要先下载对应的语言包，也可以在「系统设置 → 通用 → 语言与地区 → 翻译语言」里管理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct LanguagePackView: View {
    @EnvironmentObject private var request: TranslationDownloadRequest
    @State private var status: LanguageAvailability.Status? = nil
    @State private var configuration: TranslationSession.Configuration? = nil
    @State private var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("原文", selection: $request.source) {
                    ForEach(LanguageOption.translationTargets) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Picker("译文", selection: $request.target) {
                    ForEach(LanguageOption.translationTargets) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }
            HStack {
                Text(statusText)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("下载语言包", action: startDownload)
                    .disabled(status == .unsupported || status == .installed)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: request.pairKey) {
            await refresh()
        }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                await MainActor.run { message = "语言包已就绪" }
            } catch {
                await MainActor.run { message = "下载没有完成：\(error.localizedDescription)" }
            }
            await refresh()
        }
        .onAppear(perform: startPendingDownload)
        .onChange(of: request.pendingAutoStart) { _, _ in
            startPendingDownload()
        }
    }

    private var statusText: String {
        switch status {
        case .none: return "正在检查…"
        case .some(.installed): return "已安装"
        case .some(.supported): return "未下载"
        case .some(.unsupported): return "不支持这个语言组合"
        case .some(_): return "未知状态"
        }
    }

    private func refresh() async {
        let source = Locale.Language(identifier: request.source)
        let target = Locale.Language(identifier: request.target)
        status = await LanguageAvailability().status(from: source, to: target)
    }

    private func startPendingDownload() {
        guard request.pendingAutoStart else { return }
        request.pendingAutoStart = false
        startDownload()
    }

    private func startDownload() {
        message = nil
        let source = Locale.Language(identifier: request.source)
        let target = Locale.Language(identifier: request.target)
        if configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
    }
}

// MARK: - 同步

struct SyncSettingsView: View {
    @EnvironmentObject private var sync: CloudSync

    var body: some View {
        Form {
            Section {
                Toggle("通过 iCloud 同步设置", isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) }))
                    .disabled(!sync.isAvailableInBuild)
                LabeledContent("状态") {
                    Text(sync.statusText)
                        .foregroundStyle(.secondary)
                }
                if let date = sync.lastSyncDate {
                    LabeledContent("上次同步") {
                        Text(date.formatted(date: .abbreviated, time: .standard))
                    }
                }
                if let device = sync.lastRemoteDevice {
                    LabeledContent("云端配置来自") {
                        Text(device)
                    }
                }
                Button("立即同步") {
                    sync.syncNow()
                }
                .disabled(!sync.isEnabled || !sync.isAvailableInBuild)
            } footer: {
                Text("同步圆盘布局、已安装的功能、自己添加的插件、直达规则、唤起方式、翻译和剪贴板设置（剪贴板历史本身只留在本机）。数据存在你自己的 iCloud 账号里（iCloud 键值存储），Pop 没有任何服务器。多台 Mac 都改过时，以最后一次修改为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !sync.isAvailableInBuild {
                Section {
                    Text("当前构建没有 iCloud 能力：需要用付费开发者账号签名，并使用带 iCloud 的 entitlements（见 README）。")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 更新

struct UpdateSettingsView: View {
    @EnvironmentObject private var updates: UpdateManager

    var body: some View {
        Form {
            Section {
                LabeledContent("当前版本") {
                    Text(updates.currentVersion)
                }
                if let version = updates.pendingUpdateVersion {
                    LabeledContent("可用更新") {
                        Text(version)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Button("检查更新…") {
                    updates.checkForUpdates()
                }
                .disabled(!updates.canCheckForUpdates)
                Toggle("自动检查更新", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }
                ))
                .disabled(!updates.isConfigured)
                Toggle("自动下载并安装更新", isOn: Binding(
                    get: { updates.automaticallyDownloadsUpdates },
                    set: { updates.automaticallyDownloadsUpdates = $0 }
                ))
                .disabled(!updates.isConfigured || !updates.automaticallyChecksForUpdates)
                if let date = updates.lastUpdateCheckDate {
                    LabeledContent("上次检查") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            } footer: {
                Text("更新包从 GitHub Releases 下载，安装前会校验 EdDSA 签名。发现新版本时点「安装更新」，下载、替换、重启一步完成；打开「自动下载并安装」后会在退出 Pop 时静默安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !updates.isConfigured {
                Section {
                    Text("这是开发构建：没有配置更新签名公钥（SPARKLE_PUBLIC_ED_KEY），自动更新已关闭。发布流程见 README。")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}
