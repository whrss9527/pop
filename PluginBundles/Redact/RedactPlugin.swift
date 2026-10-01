import AppKit
@testable import Pop

/// 插件包「隐私打码」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopRedactEntry)
final class RedactEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [RedactPlugin()]
    }
}

struct RedactPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.redact, name: String(localized: "隐私打码"), symbol: "eye.slash",
                          summary: String(localized: "找出选中图片里的人脸、电话号码、邮箱、身份证号、银行卡号和车牌，打上马赛克另存一份；在本机识别，另存的那份不带拍摄信息和位置"),
                          accepts: [.imageFile])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let images = content.files.filter(ContentClassifier.isImageFile)
        guard let first = images.first else { return .failure(String(localized: "没有选中图片")) }
        let result: Result<Redaction.Preview, Redaction.Failure> = await runInBackground {
            do {
                return .success(try Redaction.preview(first, targets: Redaction.defaultTargets))
            } catch let failure as Redaction.Failure {
                return .failure(failure)
            } catch {
                return .failure(Redaction.Failure(message: error.localizedDescription))
            }
        }
        switch result {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let preview):
            return .card(Self.card(images, preview: preview))
        }
    }

    /// 预览打好码的第一张；没找到人脸和个人信息时只能选「文字也全部打码」
    static func card(_ images: [URL], preview: Redaction.Preview) -> ResultCard {
        let found = Redaction.summary(preview.regions)
        let detail: String
        if preview.regions.isEmpty {
            detail = String(localized: "没找到人脸和个人信息；要把图里的文字都打上码，点「文字也全部打码」")
        } else if images.count == 1 {
            detail = String(localized: "找到\(found)，预览里已经打上马赛克；存的时候另存一份，原图不动")
        } else {
            detail = String(localized: "第一张找到\(found)；存的时候 \(images.count) 张都会打码，各自另存一份")
        }
        var buttons: [CardButton] = []
        if !preview.regions.isEmpty || images.count > 1 {
            buttons.append(CardButton(title: String(localized: "存到原图旁边"), action: .redactImages(images, Redaction.defaultTargets)))
        }
        buttons.append(CardButton(title: String(localized: "文字也全部打码"), action: .redactImages(images, [.faces, .allText])))
        return ResultCard(title: String(localized: "隐私打码"), detail: detail, image: preview.png, buttons: buttons)
    }
}
