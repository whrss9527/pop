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

// MARK: - 暂存架

struct ShelfPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.shelf, name: String(localized: "暂存架"), symbol: "tray.full",
                          summary: String(localized: "把选中的文件放到暂存架上，之后再一起拖到别的地方；没选中文件时打开暂存架"),
                          accepts: [], optionalContent: true)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let shelf = FileShelf.shared
        shelf.add(content.files)
        shelf.show(near: context.anchor ?? NSEvent.mouseLocation)
        return .done(toast: nil)
    }
}

// MARK: - 文件信息

struct FileInfoPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.fileInfo, name: String(localized: "文件信息"), symbol: "info.circle",
                          summary: String(localized: "文件的类型、大小（文件夹算上里面所有文件）、创建和修改时间，图片尺寸和拍摄信息（相机、参数、拍摄地点）、PDF 页数、音视频时长"),
                          accepts: [.files])

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        let files = content.files
        guard let first = files.first else { return .failure(String(localized: "没有选中文件")) }
        if files.count == 1 {
            // 不在主线程上算：文件夹可能很大
            let rows = await FileInfo.rows(for: first)
            guard !rows.isEmpty else { return .failure(String(localized: "读不到「\(first.lastPathComponent)」的信息")) }
            let buttons = await runInBackground { Self.photoButtons(for: first) }
            return .card(ResultCard(title: String(localized: "文件信息"), body: first.lastPathComponent, rows: rows, buttons: buttons))
        }
        let rows = await runInBackground { FileInfo.summary(for: files) }
        return .card(ResultCard(title: String(localized: "文件信息"), body: String(localized: "\(files.count) 项"), rows: rows))
    }

    /// 照片带着拍摄地点时：在地图里看，或者另存一份去掉位置、去掉全部拍摄信息的
    static func photoButtons(for file: URL) -> [CardButton] {
        guard ContentClassifier.isImageFile(file), let metadata = PhotoMetadata.read(file), !metadata.isEmpty else { return [] }
        var buttons: [CardButton] = []
        if let map = metadata.mapURL {
            buttons.append(CardButton(title: String(localized: "在地图中打开"), action: .open(map)))
            buttons.append(CardButton(title: ImageConverter.Operation.removeLocation.title, action: .convertImages([file], .removeLocation)))
        }
        buttons.append(CardButton(title: ImageConverter.Operation.removeMetadata.title, action: .convertImages([file], .removeMetadata)))
        return buttons
    }
}
