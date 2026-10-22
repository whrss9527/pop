import AppKit
import XCTest
@testable import Pop

/// 独立宿主不编入PluginBundles源码，查询真实bundle的资源与info，不注册或执行功能。
@MainActor
final class CatalogExportTests: XCTestCase {
    private func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "Pop.CatalogContract", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    private func nullable<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }

    private func check(_ value: ContentCheck?) -> Any {
        guard let value else { return NSNull() }
        let kind: String
        switch value {
        case .colorPair: kind = "colorPair"
        case .extractable: kind = "extractable"
        case .characters: kind = "characters"
        case .lineList: kind = "lineList"
        case .yamlOrJSON: kind = "yamlOrJSON"
        case .xml: kind = "xml"
        case .sql: kind = "sql"
        case .base64Image: kind = "base64Image"
        case .twoDates: kind = "twoDates"
        case .folder: kind = "folder"
        case .twoFolders: kind = "twoFolders"
        case .markdownHeadings: kind = "markdownHeadings"
        case .idNumber: kind = "idNumber"
        case .custom(let custom): return ["kind": "custom", "id": custom.id]
        }
        return ["kind": kind]
    }

    private func function(_ info: PluginInfo, category: String) throws -> [String: Any] {
        let fields: Set<String> = ["id", "name", "symbol", "summary", "accepts", "pattern", "minLength",
                                  "maxLength", "source", "hidesOverlay", "optionalContent", "check"]
        try require(Set(Mirror(reflecting: info).children.compactMap(\.label)) == fields,
                    "PluginInfo新增字段尚未纳入静态契约")
        if let pattern = info.pattern, !pattern.isEmpty {
            _ = try NSRegularExpression(pattern: pattern) // 使用原生ICU，不用其他正则方言近似。
        }
        try require(info.minLength.map { $0 >= 0 } ?? true, "功能长度下限无效")
        try require(info.maxLength.map { $0 >= 0 } ?? true, "功能长度上限无效")
        if let minimum = info.minLength, let maximum = info.maxLength {
            try require(minimum <= maximum, "功能长度范围倒置")
        }
        try require(info.source == .builtin, "原生快照不包含用户插件")
        return ["id": info.id, "name": info.name, "summary": info.summary, "symbol": info.symbol,
                "category": category, "accepts": info.accepts.map(\.rawValue).sorted(),
                "pattern": nullable(info.pattern), "minLength": nullable(info.minLength),
                "maxLength": nullable(info.maxLength), "source": "builtin",
                "hidesOverlay": info.hidesOverlay, "optionalContent": info.optionalContent,
                "check": check(info.check)]
    }

    func testExportActualBilingualCatalog() throws {
        let language = Bundle.main.preferredLocalizations.first ?? ""
        try require(["zh-Hans", "en"].contains(language), "宿主未选择支持的快照语言")
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "PopBuildID") as? String)
        let products = Bundle.main.bundleURL.deletingLastPathComponent()
        let buildRoot = products.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var packages = PluginCatalog.packages
        var versions = [String: String]()
        // 单独发布的包从其源码描述读取包信息；功能则仍由实际编译的bundle导出。
        let folders = try FileManager.default.contentsOfDirectory(at: sourceRoot.appendingPathComponent("PluginBundles"),
                                                                  includingPropertiesForKeys: nil)
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let path = folder.appendingPathComponent("plugin.json")
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            let meta = try JSONDecoder().decode(PluginPackageMeta.self, from: Data(contentsOf: path))
            let id = try XCTUnwrap(meta.id)
            try require(!packages.contains { $0.id == id }, "独立包重复进入主程序目录")
            try require((meta.defaultsKeys ?? []).allSatisfy { $0.hasPrefix("pop.") }, "独立包偏好清理范围无效")
            let category = try XCTUnwrap(BuiltinCategory(key: meta.category))
            packages.append(PluginPackage(id: id, bundleName: "Pop" + folder.lastPathComponent,
                name: try XCTUnwrap(meta.name[language]), summary: try XCTUnwrap(meta.summary[language]),
                symbol: meta.symbol, category: category, functions: meta.functions,
                defaultsKeys: meta.defaultsKeys ?? [], keychainAccounts: meta.keychainAccounts ?? [],
                dataFolders: meta.dataFolders ?? []))
            versions[id] = try XCTUnwrap(meta.version)
        }
        try require(Set(packages.map(\.id)).count == packages.count, "包ID重复")
        var knownFunctions = Set<String>()
        var rows = [[String: Any]]()
        for package in packages {
            try require(package.bundleName.range(of: #"\APop[A-Za-z0-9_]+\z"#, options: .regularExpression) != nil,
                        "包文件名不安全")
            let url = products.appendingPathComponent(package.bundleName + ".bundle")
            try require(url.resolvingSymlinksInPath().path.hasPrefix(buildRoot.path + "/"), "包不属于当前构建")
            let bundle = try XCTUnwrap(Bundle(url: url))
            try require(bundle.object(forInfoDictionaryKey: "PopPluginID") as? String == package.id, "包ID不符")
            try require(bundle.object(forInfoDictionaryKey: "PopBuildID") as? String == build, "包与宿主构建不符")
            try require(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
                        "包与宿主版本不符")
            try require(bundle.isLoaded || bundle.load(), "无法装载当前构建的包")
            let entry = try XCTUnwrap(bundle.principalClass as? PopPluginBundle.Type)
            let infos = entry.makePlugins().map(\.info) // 不调用didLoad、willUninstall或run。
            try require(Set(infos.map(\.id)).count == infos.count, "包内功能ID重复")
            try require(Set(infos.map(\.id)) == Set(package.functions), "目录与实际makePlugins不符")
            let byID = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })
            let functions = try package.functions.map { id -> [String: Any] in
                try require(knownFunctions.insert(id).inserted, "功能归属重复")
                return try function(XCTUnwrap(byID[id]), category: package.category.key)
            }
            rows.append(["id": package.id, "bundleName": package.bundleName,
                "name": package.name, "summary": package.summary, "symbol": package.symbol,
                "category": package.category.key, "independentVersion": nullable(versions[package.id]),
                "functions": functions, "defaultsKeys": package.defaultsKeys,
                "keychainAccounts": package.keychainAccounts, "dataFolders": package.dataFolders])
        }
        let built = try FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "bundle" }
            .compactMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "PopPluginID") as? String }
        try require(Set(built) == Set(packages.map(\.id)) && built.count == packages.count,
                    "构建产物与静态目录不是同一组包")
        let host = try BuiltinPlugins.make().map { plugin -> [String: Any] in
            let info = plugin.info
            try require(knownFunctions.insert(info.id).inserted, "主程序与包功能ID重复")
            return try function(info, category: BuiltinCategory.of(info.id).key)
        }
        let snapshot: [String: Any] = ["schemaVersion": 1, "language": language,
            "appVersion": version, "buildID": build, "packages": rows, "hostFunctions": host,
            "displayOrder": BuiltinPlugins.displayOrder]
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "catalog-snapshot-\(language).json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
