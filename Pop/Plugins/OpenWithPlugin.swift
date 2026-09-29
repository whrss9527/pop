import AppKit
import SwiftUI

/// 用哪个 App 打开：选中的文件或者链接，和能打开它的 App 列表（默认的排第一个）
struct OpenWithRequest: Equatable {
    var targets: [URL]
    var apps: [URL]
}

enum OpenWith {
    /// 能打开 url 的 App：默认 App 在最前面，同一个 App 装了几份只留一个，不含 Pop 自己
    static func applications(for url: URL, limit: Int = 12) -> [URL] {
        let workspace = NSWorkspace.shared
        var candidates = workspace.urlsForApplications(toOpen: url)
        if let preferred = workspace.urlForApplication(toOpen: url) {
            candidates.removeAll { $0.standardizedFileURL == preferred.standardizedFileURL }
            candidates.insert(preferred, at: 0)
        }
        var seen = Set<String>()
        let ownID = Bundle.main.bundleIdentifier
        return Array(candidates.filter { app in
            let id = Bundle(url: app)?.bundleIdentifier ?? app.path(percentEncoded: false)
            return id != ownID && seen.insert(id).inserted
        }.prefix(limit))
    }

    static func name(of app: URL) -> String {
        let name = FileManager.default.displayName(atPath: app.path(percentEncoded: false))
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// 卡片副标题：文件名、「3 个文件」或者链接的主机名
    static func subject(of targets: [URL]) -> String {
        guard let first = targets.first else { return "" }
        if targets.count > 1 { return "\(targets.count) 个文件" }
        return first.isFileURL ? first.lastPathComponent : (first.host() ?? first.absoluteString)
    }
}

struct OpenWithPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.openWith, name: "打开方式", symbol: "arrow.up.forward.app",
                          summary: "选一个 App 打开选中的文件或链接，比如换一个浏览器打开链接", accepts: [.files, .url, .email])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let targets = content.files.isEmpty ? (content.url.map { [$0] } ?? []) : content.files
        guard let first = targets.first else { return .failure("没有可以打开的文件或链接") }
        let apps = await runInBackground { OpenWith.applications(for: first) }
        guard !apps.isEmpty else { return .failure("没有找到能打开「\(OpenWith.subject(of: targets))」的 App") }
        return .chooseApp(OpenWithRequest(targets: targets, apps: apps))
    }
}

/// 「打开方式」卡片：App 图标排成网格，点一下或按数字键打开
struct OpenWithCardView: View {
    let request: OpenWithRequest
    var onChoose: (URL) -> Void
    var onClose: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        CardContainer(title: "打开方式", subtitle: OpenWith.subject(of: request.targets), onClose: onClose) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(request.apps.enumerated()), id: \.element) { index, app in
                    AppTile(app: app, number: index < 9 ? index + 1 : nil, isDefault: index == 0) {
                        onChoose(app)
                    }
                }
            }
            Text("第一个是默认的 App；按 1–9 直接选")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 数字键 1–9 选第几个 App
    static func index(for event: NSEvent) -> Int? {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let characters = event.charactersIgnoringModifiers, let digit = Int(characters), (1...9).contains(digit) else {
            return nil
        }
        return digit - 1
    }
}

private struct AppTile: View {
    let app: URL
    let number: Int?
    let isDefault: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 36, height: 36)
                Text(OpenWith.name(of: app))
                    .font(.system(size: 10, weight: isDefault ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.14 : 0.05)))
            .overlay(alignment: .topTrailing) {
                if let number {
                    Text("\(number)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(OpenWith.name(of: app))
        .onHover { hovering = $0 }
        .animation(Motion.content, value: hovering)
    }
}
