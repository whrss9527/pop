import AppKit
@testable import Pop

/// 插件包「证件号码」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopIDNumberEntry)
final class IDNumberEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [IDNumberPlugin()]
    }
}

struct IDNumberPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.idNumber, name: String(localized: "证件号码"), symbol: "person.text.rectangle",
                          summary: String(localized: "身份证号、统一社会信用代码、银行卡号：检查校验位，读出出生日期、年龄、性别、地区和登记管理部门，不联网"),
                          accepts: [.text, .number], maxLength: 40, check: .idNumber)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let info = IDNumber.parse(text) else {
            return .failure(String(localized: "没有认出身份证号、统一社会信用代码或银行卡号"))
        }
        return .card(IDNumber.card(info))
    }
}
