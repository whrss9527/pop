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
                          summary: String(localized: "把选中的图片和 PDF 按文件名顺序合成一个 PDF；只选了一个 PDF 时可以把每页存成图片、复制里面的文字、取出其中几页或者拆开、加页码、加密码或者去掉密码，或者压缩；扫描件可以识别文字，另存一份能搜索、复制的 PDF"),
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
        // 打开 PDF 放在后台：文件很大、或者目录表坏了要从头找的，要读好一会儿
        if await runInBackground({ PDFTools.isLocked(pdf) }) {
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
            let reveal = self.reveal
            var buttons = [CardButton(title: String(localized: "每页存成图片"), action: .exportPDFPages(pdf))]
            let detail: String
            if summary.text.isEmpty {
                detail = String(localized: "\(summary.pages) 页，没有文字层：是扫描件的话可以识别文字，存成能搜索、复制的 PDF")
            } else {
                detail = String(localized: "\(summary.pages) 页，\(summary.text.count) 个字")
                buttons.append(CardButton(title: String(localized: "复制全部文字"), action: .copy(summary.text)))
            }
            // 没有文字或者只有零星几个字（扫描件上的页眉、水印）：认出文字，另存一份能搜索的
            if PDFTextLayer.needsTextLayer(characters: summary.text.count, pages: summary.pages) {
                buttons.insert(CardButton(title: String(localized: "识别文字"), action: .custom(PluginCardAction { session in
                    Self.makeSearchable(pdf, session: session, reveal: reveal)
                })), at: 1)
            }
            if summary.pages > 1 {
                buttons.append(CardButton(title: String(localized: "取出几页…"), action: .pdfPages(pdf)))
            }
            buttons.append(CardButton(title: String(localized: "加页码…"), action: .custom(PluginCardAction { session in
                Self.addPageNumbers(pdf, session: session, reveal: reveal)
            })))
            buttons.append(CardButton(title: String(localized: "加密码…"), action: .pdfPassword(pdf)))
            buttons.append(CardButton(title: String(localized: "压缩"), action: .compressPDF(pdf)))
            return .card(ResultCard(title: "PDF", body: pdf.lastPathComponent, detail: detail, buttons: buttons))
        }
    }

    /// 加页码：卡片换成选样式、位置的卡片，存好以后在访达里选中新文件
    @MainActor static func addPageNumbers(_ pdf: URL, session: PluginSession, reveal: @escaping @MainActor ([URL]) -> Void) {
        let model: PDFPageNumbersModel
        do {
            model = try PDFPageNumbersModel(pdf: pdf)
        } catch {
            session.fail((error as? PDFTools.Failure)?.message ?? error.localizedDescription)
            return
        }
        session.showCard(PDFPageNumbersView(model: model,
                                            onDone: { url in
                                                reveal([url])
                                                session.finish(toast: String(localized: "加好了页码，存成了「\(url.lastPathComponent)」"))
                                            },
                                            onClose: { session.end() }))
    }

    /// 识别文字，另存成「原名 可搜索.pdf」：卡片换成进度，认完在访达里选中新文件
    @MainActor static func makeSearchable(_ pdf: URL, session: PluginSession, reveal: @escaping @MainActor ([URL]) -> Void) {
        let destination = FileNames.available(in: pdf.deletingLastPathComponent(),
                                              base: pdf.deletingPathExtension().lastPathComponent + String(localized: " 可搜索"), extension: "pdf")
        let model = PDFTextLayerModel(pdf: pdf, destination: destination)
        session.showCard(PDFTextLayerView(model: model,
                                          onStop: {
                                              model.stop()
                                              session.end()
                                          },
                                          onClose: { session.end() }))
        model.start { result in
            switch result {
            case .success(let summary) where summary.characters == 0:
                try? FileManager.default.removeItem(at: destination)
                session.finish(toast: String(localized: "「\(pdf.lastPathComponent)」里没有认出文字"))
            case .success(let summary):
                reveal([destination])
                session.finish(toast: String(localized: "认出了 \(summary.pages) 页的文字，存成了「\(destination.lastPathComponent)」"))
            case .failure(let failure):
                session.finish(toast: failure.message)
            }
        }
    }
}
