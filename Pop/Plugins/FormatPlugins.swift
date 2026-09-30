import AppKit

// MARK: - YAML 和 JSON

struct YAMLJSONPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.yamlJSON, name: String(localized: "YAML 和 JSON"), symbol: "arrow.left.arrow.right.square",
                          summary: String(localized: "选中 JSON 转成 YAML，选中 YAML 转成 JSON，键的顺序不变"), accepts: [.text],
                          maxLength: 500_000, check: .yamlOrJSON)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有选中文字")) }
        if JSONFormatter.isJSON(text) {
            guard let value = OrderedJSON.parse(text) else { return .failure(String(localized: "不是合法的 JSON")) }
            let yaml = YAMLConverter.yaml(from: value)
            return .card(ResultCard(title: String(localized: "JSON 转 YAML"), body: yaml, monospaced: true, copyText: yaml, replaceText: yaml))
        }
        do {
            let value = try YAMLConverter.parse(text)
            let json = OrderedJSON.format(value)
            return .card(ResultCard(title: String(localized: "YAML 转 JSON"), body: json, monospaced: true, copyText: json, replaceText: json,
                                    buttons: [CardButton(title: String(localized: "复制压缩版"), action: .copy(OrderedJSON.compact(value)))]))
        } catch let failure as YAMLConverter.Failure {
            return .failure(String(localized: "读不了这段 YAML：\(failure.description)"))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

// MARK: - XML 格式化

struct FormatXMLPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.formatXML, name: String(localized: "XML 格式化"), symbol: "chevron.left.forwardslash.chevron.right",
                          summary: String(localized: "格式化或压缩选中的 XML（也认 SVG、plist、XHTML）"), accepts: [.text],
                          maxLength: 2_000_000, check: .xml)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text, let pretty = XMLFormatter.prettyPrinted(text) else { return .failure(String(localized: "不是合法的 XML")) }
        var buttons: [CardButton] = []
        if let minified = XMLFormatter.minified(text) {
            buttons.append(CardButton(title: String(localized: "复制压缩版"), action: .copy(minified)))
        }
        return .card(ResultCard(title: String(localized: "XML 格式化"), body: pretty, monospaced: true, copyText: pretty, replaceText: pretty,
                                buttons: buttons))
    }
}

// MARK: - SQL 格式化

struct FormatSQLPlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.formatSQL, name: String(localized: "SQL 格式化"), symbol: "cylinder.split.1x2",
                          summary: String(localized: "把选中的 SQL 按子句分行、关键字大写、子查询缩进，也可以压成一行"), accepts: [.text],
                          maxLength: 500_000, check: .sql)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有选中文字")) }
        let formatted = SQLFormatter.format(text)
        guard !formatted.isEmpty else { return .failure(String(localized: "没有可以格式化的 SQL")) }
        return .card(ResultCard(title: String(localized: "SQL 格式化"), body: formatted, monospaced: true, copyText: formatted, replaceText: formatted,
                                buttons: [CardButton(title: String(localized: "复制成一行"), action: .copy(SQLFormatter.format(text, compact: true)))]))
    }
}

// MARK: - Base64 图片

struct Base64ImagePlugin: PopPlugin {
    let info = PluginInfo(id: BuiltinPluginID.base64Image, name: String(localized: "Base64 图片"), symbol: "photo.artframe",
                          summary: String(localized: "把 Base64 或 data: 开头的图片数据显示成图片，可以复制、保存、贴到屏幕"), accepts: [.text],
                          maxLength: 30_000_000, check: .base64Image)

    @MainActor func run(_ content: ClassifiedContent, context: PluginContext) async -> PluginOutcome {
        guard let text = content.text else { return .failure(String(localized: "没有选中文字")) }
        let result = await runInBackground { () -> (Base64Image.Decoded, Data)? in
            guard let decoded = Base64Image.decode(text), let png = Base64Image.png(from: decoded.data) else { return nil }
            return (decoded, png)
        }
        guard let (decoded, png) = result else { return .failure(String(localized: "解不出图片")) }
        let rows = [
            ResultCard.Row(label: String(localized: "格式"), value: decoded.type.preferredFilenameExtension?.uppercased() ?? decoded.type.identifier),
            ResultCard.Row(label: String(localized: "尺寸"), value: "\(decoded.width) × \(decoded.height)"),
            ResultCard.Row(label: String(localized: "大小"), value: FileInfo.shortSize(Int64(decoded.data.count))),
        ]
        return .card(ResultCard(title: String(localized: "Base64 图片"), rows: rows, image: png, buttons: [
            CardButton(title: String(localized: "复制图片"), action: .copyImage(png)),
            CardButton(title: String(localized: "存到「下载」"), action: .saveImage(png, name: ImageFiles.timestampedName(String(localized: "Base64 图片")))),
            CardButton(title: String(localized: "贴到屏幕"), action: .pinImage(png)),
        ]))
    }
}
