import AppKit
@testable import Pop

/// 插件包「传到手机」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopSendToPhoneEntry)
final class SendToPhoneEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [SendToPhonePlugin()]
    }

    @MainActor static func willUninstall() {
        PhoneShare.shared.stop()
    }
}

/// 传到手机：在局域网里开一个临时网页，手机扫码下载选中的文件，也能把手机里的文件传到 Mac
struct SendToPhonePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.sendToPhone, name: String(localized: "传到手机"), symbol: "iphone.radiowaves.left.and.right",
                          summary: String(localized: "手机扫码下载选中的文件、图片（文件夹先打包成 zip）或者拿到选中的文字，也能从手机传文件到「下载」文件夹；手机和 Mac 连同一个 Wi-Fi 就行，安卓手机也能用"),
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let prepared: (files: [URL], text: String?, scratch: URL?)
        do {
            prepared = try await PhoneShare.prepare(content)
        } catch {
            return .failure((error as? PhoneShare.Failure)?.message ?? error.localizedDescription)
        }
        do {
            let address = try await PhoneShare.shared.share(prepared.files, text: prepared.text, scratch: prepared.scratch)
            return .card(PhoneShare.card(address: address, files: prepared.files, text: prepared.text))
        } catch {
            if let scratch = prepared.scratch {
                try? FileManager.default.removeItem(at: scratch)
            }
            return .failure((error as? PhoneShare.Failure)?.message ?? error.localizedDescription)
        }
    }
}
