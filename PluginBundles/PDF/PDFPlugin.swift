import AppKit
@testable import Pop

/// 插件包「PDF」的入口（Info.plist 的 NSPrincipalClass）
@objc(PopPDFEntry)
final class PDFEntry: NSObject, PopPluginBundle {
    static func makePlugins() -> [any PopPlugin] {
        [PDFPlugin()]
    }
}

struct PDFPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.pdf, name: "PDF", symbol: "doc.richtext",
                          summary: String(localized: "把选中的图片和 PDF 按文件名顺序合成一个 PDF；只选了一个 PDF 时可以把每页存成图片、复制里面的文字、取出其中几页或者拆开、加密码或者去掉密码，或者压缩"),
                          accepts: [.files], pattern: #"(?im)\.(pdf|png|jpe?g|heic|heif|tiff?|gif|bmp|webp)$"#)
    /// 完成后在访达里选中结果（测试时换掉）
    var reveal: @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = PDFTools.sorted(content.files.filter { PDFTools.isPDF($0) || PDFTools.isImage($0) })
        guard let first = files.first else { return .failure(String(localized: "选中的文件里没有 PDF 或图片")) }
        if files.count == 1, PDFTools.isPDF(first) {
            return await summary(of: first)
        }
        // 合成的 PDF 放在第一个文件旁边
        let base = first.deletingPathExtension().lastPathComponent
        let destination = FileNames.available(in: first.deletingLastPathComponent(),
                                              base: files.count == 1 ? base : String(localized: "\(base) 等 \(files.count) 个文件"),
                                              extension: "pdf")
        let result = await runInBackground { () -> Result<Int, PDFTools.Failure> in
            do {
                return .success(try PDFTools.combine(files, into: destination))
            } catch let failure as PDFTools.Failure {
                return .failure(failure)
            } catch {
                return .failure(PDFTools.Failure(message: error.localizedDescription))
            }
        }
        switch result {
        case .success(let pages):
            reveal([destination])
            return .done(toast: String(localized: "已合成 \(pages) 页的 PDF"))
        case .failure(let failure):
            try? FileManager.default.removeItem(at: destination)
            return .failure(failure.message)
        }
    }

    /// 一个 PDF：列出页数，可以把每页存成图片、复制全部文字；有密码的可以去掉密码
    @MainActor private func summary(of pdf: URL) async -> PluginOutcome {
        if PDFTools.isLocked(pdf) {
            return .card(ResultCard(title: "PDF", body: pdf.lastPathComponent, detail: String(localized: "有密码，先去掉密码才能取页、压缩或者复制文字"),
                                    buttons: [CardButton(title: String(localized: "去掉密码…"), action: .pdfPassword(pdf))]))
        }
        let result = await runInBackground { () -> Result<(pages: Int, text: String), PDFTools.Failure> in
            do {
                let document = try PDFTools.open(pdf)
                return .success((document.pageCount, document.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
            } catch let failure as PDFTools.Failure {
                return .failure(failure)
            } catch {
                return .failure(PDFTools.Failure(message: error.localizedDescription))
            }
        }
        switch result {
        case .failure(let failure):
            return .failure(failure.message)
        case .success(let summary):
            var buttons = [CardButton(title: String(localized: "每页存成图片"), action: .exportPDFPages(pdf))]
            let detail: String
            if summary.text.isEmpty {
                detail = String(localized: "\(summary.pages) 页，没有文字层（扫描件可以先存成图片，再用「识别文字」）")
            } else {
                detail = String(localized: "\(summary.pages) 页，\(summary.text.count) 个字")
                buttons.append(CardButton(title: String(localized: "复制全部文字"), action: .copy(summary.text)))
            }
            if summary.pages > 1 {
                buttons.append(CardButton(title: String(localized: "取出几页…"), action: .pdfPages(pdf)))
            }
            buttons.append(CardButton(title: String(localized: "加密码…"), action: .pdfPassword(pdf)))
            buttons.append(CardButton(title: String(localized: "压缩"), action: .compressPDF(pdf)))
            return .card(ResultCard(title: "PDF", body: pdf.lastPathComponent, detail: detail, buttons: buttons))
        }
    }
}
