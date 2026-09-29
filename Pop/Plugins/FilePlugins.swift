import AppKit

/// 在文件夹里找一个还没被占用的名字：「名字.扩展名」，有了就「名字 2.扩展名」……
enum FileNames {
    static func available(in folder: URL, base: String, extension ext: String? = nil) -> URL {
        func candidate(_ suffix: String) -> URL {
            let name = base + suffix
            return folder.appending(path: ext.map { "\(name).\($0)" } ?? name)
        }
        var url = candidate("")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = candidate(" \(counter)")
            counter += 1
        }
        return url
    }
}

// MARK: - 压缩和解压

struct ZipPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.zip, name: "压缩", symbol: "doc.zipper",
                          summary: "把选中的文件或文件夹压缩成 zip，存在原来的文件夹里", accepts: [.files])
    /// 完成后在访达里选中结果（测试时换掉）
    var reveal: @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files
        guard let first = files.first else { return .failure("没有选中文件") }
        let folder = first.deletingLastPathComponent()
        guard files.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }) else {
            return .failure("选中的文件不在同一个文件夹里")
        }
        let base = files.count == 1 ? first.deletingPathExtension().lastPathComponent : "归档"
        let destination = FileNames.available(in: folder, base: base, extension: "zip")
        let result: Result<ProcessRunner.Output, PluginRunError>
        if files.count == 1 {
            // ditto 和访达的「压缩」一样：保留扩展属性，解压后还是原来的样子
            result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                             arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                                         first.path(percentEncoded: false), destination.path(percentEncoded: false)],
                                             stdin: nil, environment: [:], timeout: 600)
        } else {
            // 多个文件：在它们所在的文件夹里用相对路径打包，压缩包里不带上层目录
            result = await ProcessRunner.run(URL(fileURLWithPath: "/bin/zsh"),
                                             arguments: ["-c", #"cd "$1" && dest="$2" && shift 2 && /usr/bin/zip -r -q -y "$dest" "$@""#, "zsh",
                                                         folder.path(percentEncoded: false), destination.path(percentEncoded: false)]
                                                 + files.map(\.lastPathComponent),
                                             stdin: nil, environment: [:], timeout: 600)
        }
        if let problem = Self.problem(in: result) {
            try? FileManager.default.removeItem(at: destination)
            return .failure("压缩失败：\(problem)")
        }
        reveal([destination])
        return .done(toast: "已压缩成 \(destination.lastPathComponent)")
    }

    /// 子进程失败时的原因；成功返回 nil
    static func problem(in result: Result<ProcessRunner.Output, PluginRunError>) -> String? {
        switch result {
        case .failure(let error):
            return error.message
        case .success(let output):
            if output.timedOut {
                return "超时了"
            }
            guard output.status == 0 else {
                let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty ? "退出码 \(output.status)" : String(message.prefix(300))
            }
            return nil
        }
    }
}

struct UnzipPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.unzip, name: "解压", symbol: "archivebox",
                          summary: "把选中的 zip 解压到旁边的同名文件夹里", accepts: [.files], pattern: #"(?i)\.zip$"#)
    /// 完成后在访达里选中结果（测试时换掉）
    var reveal: @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let archives = content.files.filter { $0.pathExtension.lowercased() == "zip" }
        guard !archives.isEmpty else { return .failure("没有选中 zip 文件") }
        var folders: [URL] = []
        for archive in archives {
            let destination = FileNames.available(in: archive.deletingLastPathComponent(),
                                                  base: archive.deletingPathExtension().lastPathComponent)
            let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                                 arguments: ["-x", "-k", archive.path(percentEncoded: false),
                                                             destination.path(percentEncoded: false)],
                                                 stdin: nil, environment: [:], timeout: 600)
            if let problem = ZipPlugin.problem(in: result) {
                return .failure("解压「\(archive.lastPathComponent)」失败：\(problem)")
            }
            folders.append(destination)
        }
        reveal(folders)
        return .done(toast: folders.count == 1 ? "已解压到「\(folders[0].lastPathComponent)」" : "已解压 \(folders.count) 个文件")
    }
}

// MARK: - 表格

struct TableConvertPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.tableConvert, name: "表格转换", symbol: "tablecells",
                          summary: "从表格软件复制的文字、CSV、Markdown 表格互相转换，也能转成 JSON", accepts: [.text],
                          pattern: #"[\t,|][^\n]*\n[^\n]*[\t,|]"#, maxLength: 500_000)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure("没有文字") }
        guard let table = await runInBackground({ TableConverter.parse(text) }) else {
            return .failure("这段文字不像表格：需要至少两行两列，并且每行的列数一样。")
        }
        let columns = table.rows.first?.count ?? 0
        let rows = await runInBackground { TableConverter.conversions(table) }
        return .card(ResultCard(title: "表格转换", detail: "\(table.rows.count) 行 × \(columns) 列（第一行当作表头）",
                                rows: rows, rowsReplaceable: true, rowLineLimit: 3))
    }
}

// MARK: - PDF

struct PDFPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.pdf, name: "PDF", symbol: "doc.richtext",
                          summary: "把选中的图片和 PDF 按文件名顺序合成一个 PDF；只选了一个 PDF 时可以把每页存成图片或者复制里面的文字",
                          accepts: [.files], pattern: #"(?im)\.(pdf|png|jpe?g|heic|heif|tiff?|gif|bmp|webp)$"#)
    /// 完成后在访达里选中结果（测试时换掉）
    var reveal: @MainActor ([URL]) -> Void = { NSWorkspace.shared.activateFileViewerSelecting($0) }

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = PDFTools.sorted(content.files.filter { PDFTools.isPDF($0) || PDFTools.isImage($0) })
        guard let first = files.first else { return .failure("选中的文件里没有 PDF 或图片") }
        if files.count == 1, PDFTools.isPDF(first) {
            return await summary(of: first)
        }
        // 合成的 PDF 放在第一个文件旁边
        let base = first.deletingPathExtension().lastPathComponent
        let destination = FileNames.available(in: first.deletingLastPathComponent(),
                                              base: files.count == 1 ? base : "\(base) 等 \(files.count) 个文件",
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
            return .done(toast: "已合成 \(pages) 页的 PDF")
        case .failure(let failure):
            try? FileManager.default.removeItem(at: destination)
            return .failure(failure.message)
        }
    }

    /// 一个 PDF：列出页数，可以把每页存成图片、复制全部文字
    @MainActor private func summary(of pdf: URL) async -> PluginOutcome {
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
            var buttons = [CardButton(title: "每页存成图片", action: .exportPDFPages(pdf))]
            let detail: String
            if summary.text.isEmpty {
                detail = "\(summary.pages) 页，没有文字层（扫描件可以先存成图片，再用「识别文字」）"
            } else {
                detail = "\(summary.pages) 页，\(summary.text.count) 个字"
                buttons.append(CardButton(title: "复制全部文字", action: .copy(summary.text)))
            }
            return .card(ResultCard(title: "PDF", body: pdf.lastPathComponent, detail: detail, buttons: buttons))
        }
    }
}

// MARK: - 暂存架

struct ShelfPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.shelf, name: "暂存架", symbol: "tray.full",
                          summary: "把选中的文件放到暂存架上，之后再一起拖到别的地方；没选中文件时打开暂存架",
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let shelf = FileShelf.shared
        shelf.add(content.files)
        shelf.show(near: context.anchor ?? NSEvent.mouseLocation)
        return .done(toast: nil)
    }
}
