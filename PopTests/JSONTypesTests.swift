import XCTest
@testable import Pop

final class JSONTypesTests: XCTestCase {
    private let sample = #"{"id": 1, "user_name": "a", "tags": ["x"], "profile": {"url": "u", "age": null}, "#
        + #""items": [{"sku": "A", "price": 9.5}, {"sku": "B", "price": 10, "note": "n"}], "default": true}"#

    private func code(_ json: String, _ language: JSONTypes.Language) -> String? {
        JSONTypes.generate(json)?.code.first { $0.language == language }?.text
    }

    func testTypeScript() {
        XCTAssertEqual(JSONTypes.generate(sample)?.typeCount, 3)
        XCTAssertEqual(code(sample, .typeScript), """
        export interface Root {
          id: number;
          user_name: string;
          tags: string[];
          profile: Profile;
          items: Item[];
          default: boolean;
        }

        export interface Profile {
          url: string;
          age: unknown;
        }

        export interface Item {
          sku: string;
          price: number;
          note?: string;
        }
        """)
    }

    func testSwift() {
        XCTAssertEqual(code(sample, .swift), """
        struct Root: Codable {
            let id: Int
            let userName: String
            let tags: [String]
            let profile: Profile
            let items: [Item]
            let `default`: Bool

            enum CodingKeys: String, CodingKey {
                case id
                case userName = "user_name"
                case tags
                case profile
                case items
                case `default`
            }
        }

        struct Profile: Codable {
            let url: String
            let age: String? // 示例里只有 null 或空数组，看不出类型
        }

        struct Item: Codable {
            let sku: String
            let price: Double
            let note: String?
        }
        """)
    }

    func testGo() throws {
        let go = try XCTUnwrap(code(sample, .go))
        XCTAssertTrue(go.hasPrefix("type Root struct {\n\tID       int      `json:\"id\"`\n"), go)
        XCTAssertTrue(go.contains("\tUserName string   `json:\"user_name\"`"), go)
        XCTAssertTrue(go.contains("\tAge any    `json:\"age\"`"), go)
        XCTAssertTrue(go.contains("\tNote  *string `json:\"note,omitempty\"`"), go)
    }

    func testKotlin() throws {
        let kotlin = try XCTUnwrap(code(sample, .kotlin))
        XCTAssertTrue(kotlin.hasPrefix("""
        import kotlinx.serialization.SerialName
        import kotlinx.serialization.Serializable
        import kotlinx.serialization.json.JsonElement

        @Serializable
        data class Root(
            val id: Int,
            @SerialName("user_name")
            val userName: String,
        """), kotlin)
        XCTAssertTrue(kotlin.contains("    val age: JsonElement? = null,"), kotlin)
        XCTAssertTrue(kotlin.contains("    val note: String? = null,"), kotlin)
    }

    func testShapesAndNames() {
        // 根是数组：合并所有元素，有的元素里没有的字段是可选的
        XCTAssertEqual(code(#"[{"a": 1}, {"a": 2, "b": "x"}]"#, .typeScript), "export interface Item {\n  a: number;\n  b?: string;\n}")
        // 键的顺序和原文一样
        XCTAssertEqual(code(#"{"z": 1, "a": 2}"#, .typeScript), "export interface Root {\n  z: number;\n  a: number;\n}")
        // 超出 32 位的整数
        let big = #"{"big": 3000000000, "small": 1}"#
        XCTAssertEqual(code(big, .kotlin)?.contains("val big: Long,"), true)
        XCTAssertEqual(code(big, .go)?.contains("\tBig   int64"), true)
        // 类型不固定、只有 null
        let mixed = code(#"{"v": [1, "a"], "w": null}"#, .typeScript)
        XCTAssertEqual(mixed?.contains("  v: (string | number)[];"), true)
        XCTAssertEqual(mixed?.contains("  w: unknown;"), true)
        // 和自带类型重名的加上 Info；数组元素用单数
        let reserved = code(#"{"data": {"x": 1}, "list": [{"y": true}], "categories": [{"z": 1}]}"#, .typeScript) ?? ""
        XCTAssertTrue(reserved.contains("  data: DataInfo;"), reserved)
        XCTAssertTrue(reserved.contains("export interface DataInfo {"), reserved)
        XCTAssertTrue(reserved.contains("  list: ListItem[];"), reserved)
        XCTAssertTrue(reserved.contains("  categories: Category[];"), reserved)
        // 不能直接当属性名的键
        let keys = #"{"first-name": "a", "2fa": true}"#
        XCTAssertEqual(code(keys, .typeScript)?.contains(#"  "first-name": string;"#), true)
        XCTAssertEqual(code(keys, .swift)?.contains(#"        case _2fa = "2fa""#), true)
        XCTAssertEqual(code(keys, .go)?.contains("\tX2fa"), true)
    }

    func testNothingToGenerate() {
        XCTAssertNil(JSONTypes.generate("[1, 2]"))
        XCTAssertNil(JSONTypes.generate("{oops"))
    }

    func testNaming() {
        XCTAssertEqual(JSONTypes.words("URLPath"), ["URL", "Path"])
        XCTAssertEqual(JSONTypes.words("first_name"), ["first", "name"])
        XCTAssertEqual(JSONTypes.camelCase("first_name"), "firstName")
        XCTAssertEqual(JSONTypes.camelCase("URLPath"), "urlPath")
        XCTAssertEqual(JSONTypes.goName("user_id"), "UserID")
        XCTAssertEqual(JSONTypes.goName("api_url"), "APIURL")
        XCTAssertEqual(JSONTypes.typeName("user_info"), "UserInfo")
        XCTAssertEqual(JSONTypes.singular("Categories"), "Category")
        XCTAssertEqual(JSONTypes.singular("Boxes"), "Box")
        XCTAssertEqual(JSONTypes.singular("Items"), "Item")
        XCTAssertEqual(JSONTypes.singular("Status"), "StatusItem")
        XCTAssertEqual(JSONTypes.singular("Data"), "DataItem")
    }

    func testReader() {
        XCTAssertNotNil(JSONReader.parse(#"{"a": "中😀", "b": [1, 2.5e3, -0, true, null]}"#))
        XCTAssertNil(JSONReader.parse(#"{"a": 01}"#))
        XCTAssertNil(JSONReader.parse("[1,]"))
        XCTAssertNil(JSONReader.parse(#"{"a": 1} x"#))
        XCTAssertNil(JSONReader.parse(String(repeating: "[", count: 500) + String(repeating: "]", count: 500)))
    }

    @MainActor
    func testPluginShowsOneTabPerLanguage() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let outcome = await JSONTypesPlugin().run(ContentClassifier.classify(.text(sample)), context: context)
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.tabs.map(\.title), ["TypeScript", "Swift", "Go", "Kotlin"])
        XCTAssertNil(card.copyText)
    }
}
