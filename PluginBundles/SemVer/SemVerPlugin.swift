import AppKit
@testable import Pop

extension Bundle {
    /// 独立插件的文字只从自己的资源包读取。
    static let semVer = Bundle(for: SemVerEntry.self)
}

@objc(PopSemVerEntry)
final class SemVerEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] { [SemVerPlugin()] }
}

struct SemVerPlugin: PopPlugin {
    static let id = "semver"

    let info = PluginInfo(id: Self.id, name: String(localized: "语义版本", bundle: .semVer),
                          symbol: "number.square", summary: String(localized: "比较或排序选中的语义版本，每行一个；遵循 SemVer 2.0，构建信息不影响优先级，全程离线", bundle: .semVer),
                          accepts: [.text], maxLength: SemanticVersionList.maximumTextLength)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else {
            return .failure(String(localized: "至少选择两个版本号，每行一个", bundle: .semVer))
        }
        let result = await runInBackground { Result { try SemanticVersionList.parse(text) } }
        switch result {
        case .success(let list):
            let relation: String
            if list.versions.count == 2 {
                let first = list.versions[0]
                let second = list.versions[1]
                let comparison = first.comparePrecedence(to: second)
                let symbol = comparison == .orderedSame ? "=" : (comparison == .orderedAscending ? "<" : ">")
                relation = "\(first.rawValue) \(symbol) \(second.rawValue)"
            } else {
                relation = ""
            }
            return .card(ResultCard(title: String(localized: "语义版本", bundle: .semVer), body: relation,
                                    detail: String(localized: "比较的是版本优先级；+ 后的构建信息不参与排序，相同优先级保持原序", bundle: .semVer),
                                    monospaced: true,
                                    rows: [
                                        ResultCard.Row(label: String(localized: "升序", bundle: .semVer), value: list.sorted().joined(separator: "\n")),
                                        ResultCard.Row(label: String(localized: "降序", bundle: .semVer), value: list.sorted(descending: true).joined(separator: "\n"))
                                    ], rowsReplaceable: true))
        case .failure(let error):
            switch error as? SemanticVersionList.ParseError {
            case .tooLong?:
                return .failure(String(localized: "版本列表过长，请缩短后重试", bundle: .semVer))
            case .tooFewVersions?:
                return .failure(String(localized: "至少选择两个版本号，每行一个", bundle: .semVer))
            case .tooManyVersions?:
                return .failure(String(localized: "一次最多比较 200 个版本号", bundle: .semVer))
            case .invalidVersion(let line)?:
                return .failure(String(localized: "第 \(line) 行不是严格的 SemVer 2.0 版本号", bundle: .semVer))
            case nil:
                return .failure(String(localized: "无法读取版本列表", bundle: .semVer))
            }
        }
    }
}
