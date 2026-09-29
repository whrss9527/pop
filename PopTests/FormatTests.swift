import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Pop

final class YAMLAndJSONTests: XCTestCase {
    private let sampleJSON = #"""
    {"name": "pop", "version": "0.15.0", "debug": false, "ports": [80, 443], "owner": {"login": "whrss9527", "site": null},
     "tags": ["效率", "mac app"], "empty": {}, "none": [], "note": "第一行\n第二行\n", "matrix": [[1, 2], [3]],
     "steps": [{"name": "build", "run": "make"}, {"name": "test"}], "yes": "yes", "price": 1.50, "date": "2026-09-29"}
    """#

    func testOrderedJSONKeepsOrderAndNumbers() throws {
        let value = try XCTUnwrap(OrderedJSON.parse(#"{"b": 1, "a": [1.50, -2e3, true, null], "s": "\u6548\ud83d\ude00\n\"x\""}"#))
        XCTAssertEqual(OrderedJSON.format(value), #"""
        {
          "b": 1,
          "a": [
            1.50,
            -2e3,
            true,
            null
          ],
          "s": "效😀\n\"x\""
        }
        """#)
        XCTAssertEqual(OrderedJSON.compact(value), #"{"b":1,"a":[1.50,-2e3,true,null],"s":"效😀\n\"x\""}"#)
        XCTAssertNil(OrderedJSON.parse(#"{"a": 1,}"#))
        XCTAssertNil(OrderedJSON.parse("{'a': 1}"))
        XCTAssertNil(OrderedJSON.parse(#"{"a": 1}x"#))
    }

    func testJSONToYAML() throws {
        let value = try XCTUnwrap(OrderedJSON.parse(sampleJSON))
        XCTAssertEqual(YAMLConverter.yaml(from: value), """
        name: pop
        version: "0.15.0"
        debug: false
        ports:
          - 80
          - 443
        owner:
          login: whrss9527
          site: null
        tags:
          - 效率
          - mac app
        empty: {}
        none: []
        note: |
          第一行
          第二行
        matrix:
          - - 1
            - 2
          - - 3
        steps:
          - name: build
            run: make
          - name: test
        "yes": "yes"
        price: 1.50
        date: "2026-09-29"
        """)
        // 写出来的 YAML 读回去和原来一样
        XCTAssertEqual(try YAMLConverter.parse(YAMLConverter.yaml(from: value)), value)
    }

    func testYAMLToJSON() throws {
        let config = """
        # 服务配置
        name: pop
        version: 0.15.0
        port: 8080
        ratio: .5
        hex: 0x1F
        debug: false
        tags: [效率, "mac app"]
        env: {HOME: /Users/pop, LANG: zh_CN.UTF-8}
        message: >
          first line
          second line
        quote: 'it''s'
        empty:
        """
        XCTAssertEqual(OrderedJSON.format(try YAMLConverter.parse(config)), #"""
        {
          "name": "pop",
          "version": "0.15.0",
          "port": 8080,
          "ratio": 0.5,
          "hex": 31,
          "debug": false,
          "tags": [
            "效率",
            "mac app"
          ],
          "env": {
            "HOME": "/Users/pop",
            "LANG": "zh_CN.UTF-8"
          },
          "message": "first line second line\n",
          "quote": "it's",
          "empty": null
        }
        """#)

        // 键下面同样缩进的列表、「- key: value」、多行文字里的 #
        let workflow = """
        steps:
        - name: build
          run: make
        - name: test
          run: |
            make test
            echo "# done"
        """
        XCTAssertEqual(OrderedJSON.compact(try YAMLConverter.parse(workflow)),
                       ##"{"steps":[{"name":"build","run":"make"},{"name":"test","run":"make test\necho \"# done\"\n"}]}"##)

        // 保留结尾空行、去掉结尾换行、嵌套列表、跨行的 [ ]、顶层列表
        XCTAssertEqual(OrderedJSON.compact(try YAMLConverter.parse("keep: |+\n  text\n\nstrip: |-\n  a\n  b\n")),
                       #"{"keep":"text\n\n","strip":"a\nb"}"#)
        XCTAssertEqual(OrderedJSON.compact(try YAMLConverter.parse("matrix:\n  - - a\n    - b\n  - - c\n")), #"{"matrix":[["a","b"],["c"]]}"#)
        XCTAssertEqual(OrderedJSON.compact(try YAMLConverter.parse("args: [\n  \"--flag\",\n  value,\n]\n")), #"{"args":["--flag","value"]}"#)
        XCTAssertEqual(OrderedJSON.compact(try YAMLConverter.parse("- 1\n- two\n- {three: 3}\n")), #"[1,"two",{"three":3}]"#)
        XCTAssertEqual(OrderedJSON.compact(try YAMLConverter.parse("a: \"x: y # 不是注释\"\nb: plain text # 注释\nc: multi\n  line plain\n")),
                       #"{"a":"x: y # 不是注释","b":"plain text","c":"multi line plain"}"#)
    }

    func testYAMLErrorsNameTheLine() {
        func failure(_ text: String) -> YAMLConverter.Failure? {
            do {
                _ = try YAMLConverter.parse(text)
                return nil
            } catch {
                return error as? YAMLConverter.Failure
            }
        }
        XCTAssertEqual(failure("a: 1\na: 2\n"), YAMLConverter.Failure(message: "键「a」重复了", line: 2))
        XCTAssertEqual(failure("a: &x 1\n")?.line, 1)
        XCTAssertEqual(failure("a: 1\n---\nb: 2\n")?.line, 2)
        XCTAssertEqual(failure("a:\n  b: 1\n c: 2\n"), YAMLConverter.Failure(message: "缩进不对", line: 3))
        XCTAssertEqual(failure("a:\n  b: 1\n c: 2\n")?.description, "第 3 行：缩进不对")
    }

    func testLooksLikeYAML() {
        XCTAssertTrue(YAMLConverter.looksLikeYAML("name: pop\nports:\n  - 80\n"))
        XCTAssertFalse(YAMLConverter.looksLikeYAML("Note: remember to bring the book"))
        XCTAssertFalse(YAMLConverter.looksLikeYAML(#"{"a": 1, "b": 2}"#))
        XCTAssertFalse(YAMLConverter.looksLikeYAML("hello world\nthis is text"))
    }

    func testPlainScalarsNeedQuotesWhenAmbiguous() {
        for text in ["", "true", "null", "123", "1.5", "yes", "a: b", "- item", "#tag", " lead", "2026-09-29", "1:20"] {
            XCTAssertFalse(YAMLConverter.canBePlain(text), text)
        }
        for text in ["pop", "mac app", "效率", "https://example.com/a?b=c#frag", "say \"hi\""] {
            XCTAssertTrue(YAMLConverter.canBePlain(text), text)
        }
    }

    @MainActor
    func testPluginConvertsBothWays() async {
        let context = PluginContext(settings: AppSettings(), openSettings: {})
        let json = await YAMLJSONPlugin().run(ContentClassifier.classify(.text(#"{"a": [1, 2]}"#)), context: context)
        guard case .card(let toYAML) = json else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(toYAML.title, "JSON 转 YAML")
        XCTAssertEqual(toYAML.body, "a:\n  - 1\n  - 2")

        let yaml = await YAMLJSONPlugin().run(ContentClassifier.classify(.text("a: 1\nb:\n  - x\n")), context: context)
        guard case .card(let toJSON) = yaml else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(toJSON.title, "YAML 转 JSON")
        XCTAssertEqual(toJSON.buttons.first?.action, .copy(#"{"a":1,"b":["x"]}"#))

        let broken = await YAMLJSONPlugin().run(ContentClassifier.classify(.text("a: 1\na: 2\n")), context: context)
        XCTAssertEqual(broken, .failure("读不了这段 YAML：第 2 行：键「a」重复了"))
    }
}

final class SQLFormatterTests: XCTestCase {
    func testFormatsClausesListsAndConditions() {
        let sql = "select id, name, count(*) as total from users u left join orders o on o.user_id = u.id "
            + "where u.active = true and o.created_at between '2026-01-01' and '2026-09-29' or u.vip "
            + "group by id, name order by total desc limit 10"
        XCTAssertEqual(SQLFormatter.format(sql), """
        SELECT
          id,
          name,
          count(*) AS total
        FROM users u
        LEFT JOIN orders o ON o.user_id = u.id
        WHERE u.active = TRUE
          AND o.created_at BETWEEN '2026-01-01' AND '2026-09-29'
          OR u.vip
        GROUP BY id, name
        ORDER BY total DESC
        LIMIT 10
        """)
    }

    func testSubqueriesInsertUpdateAndWith() {
        XCTAssertEqual(SQLFormatter.format("SELECT a.* FROM a WHERE id IN (SELECT id FROM b WHERE x > 1) AND y = 2;"), """
        SELECT a.*
        FROM a
        WHERE id IN (
          SELECT id
          FROM b
          WHERE x > 1
        )
          AND y = 2;
        """)
        XCTAssertEqual(SQLFormatter.format("insert into t (a, b) values (1, 'x'), (2, 'it''s')"), """
        INSERT INTO t (a, b)
        VALUES
          (1, 'x'),
          (2, 'it''s')
        """)
        XCTAssertEqual(SQLFormatter.format("update users set name = 'pop', age = age + 1 where id = 3"), """
        UPDATE users
        SET
          name = 'pop',
          age = age + 1
        WHERE id = 3
        """)
        XCTAssertEqual(SQLFormatter.format("with recent as (select * from orders where created_at > now() - interval '7 days') select count(*) from recent"), """
        WITH recent AS (
          SELECT *
          FROM orders
          WHERE created_at > now() - INTERVAL '7 days'
        )
        SELECT count(*)
        FROM recent
        """)
    }

    func testSignsCastsCommentsAndOneLine() {
        let sql = "select -1, x - 1, price::numeric from t -- comment\nwhere a = -2"
        XCTAssertEqual(SQLFormatter.format(sql), """
        SELECT
          -1,
          x - 1,
          price::numeric
        FROM t -- comment
        WHERE a = -2
        """)
        XCTAssertEqual(SQLFormatter.format(sql, compact: true), "SELECT -1, x - 1, price::numeric FROM t /* comment */ WHERE a = -2")
        XCTAssertEqual(SQLFormatter.format("SELECT a.* FROM a WHERE id IN (SELECT id FROM b WHERE x > 1) AND y = 2;", compact: true),
                       "SELECT a.* FROM a WHERE id IN (SELECT id FROM b WHERE x > 1) AND y = 2;")
    }

    func testRecognizesSQLButNotSentences() {
        for sql in ["select id, name from users where id = 1", "SELECT name FROM users", "update users set name = 'pop' where id = 1",
                    "with recent as (select 1) select * from recent", "CREATE TABLE users (id INT)", "insert into t (a) values (1)"] {
            XCTAssertTrue(SQLFormatter.looksLikeSQL(sql), sql)
        }
        for sentence in ["Select the file from the list.", "Delete from the list any old items",
                         "Update your profile and set a new password", "create table of contents for the report"] {
            XCTAssertFalse(SQLFormatter.looksLikeSQL(sentence), sentence)
        }
    }

    func testCodeIsNotTranslatedAutomatically() {
        XCTAssertFalse(ContentClassifier.classify(.text("SELECT id, name FROM users WHERE id = 1")).kinds.contains(.foreignText))
        XCTAssertFalse(ContentClassifier.classify(.text("<note><to>Tove</to><from>Jani</from></note>")).kinds.contains(.foreignText))
        XCTAssertTrue(ContentClassifier.classify(.text("Select the file from the list.")).kinds.contains(.foreignText))
    }
}

final class XMLFormatterTests: XCTestCase {
    func testFormatsAndMinifies() throws {
        let xml = "<root>\n      <a x=\"1\">hi</a>\n  <b/></root>"
        XCTAssertTrue(XMLFormatter.isXML(xml))
        XCTAssertFalse(XMLFormatter.isXML("<b>bold"))
        XCTAssertFalse(XMLFormatter.isXML("a < b > c"))
        let pretty = try XCTUnwrap(XMLFormatter.prettyPrinted(xml))
        let lines = pretty.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains { $0.hasPrefix(" ") && $0.trimmingCharacters(in: .whitespaces) == "<a x=\"1\">hi</a>" }, pretty)
        XCTAssertTrue(lines.contains { $0.trimmingCharacters(in: .whitespaces) == "<b/>" }, pretty)
        XCTAssertTrue(try XCTUnwrap(XMLFormatter.minified(xml)).hasSuffix("<root><a x=\"1\">hi</a><b/></root>"))
    }
}

final class Base64ImageTests: XCTestCase {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testDecodesBase64AndDataURIs() throws {
        let base64 = try pngData(width: 3, height: 2).base64EncodedString()
        for text in [base64, "data:image/png;base64," + base64, String(base64.prefix(40)) + "\n" + String(base64.dropFirst(40))] {
            XCTAssertTrue(Base64Image.looksLikeImage(text))
            let decoded = try XCTUnwrap(Base64Image.decode(text))
            XCTAssertEqual(decoded.type, .png)
            XCTAssertEqual(decoded.width, 3)
            XCTAssertEqual(decoded.height, 2)
        }
        // 解出来不是图片的 Base64、不是 Base64 的文字
        XCTAssertFalse(Base64Image.looksLikeImage(Data("Hello world, this is plain text".utf8).base64EncodedString()))
        XCTAssertNil(Base64Image.payload("not base64 at all, just words!"))
        XCTAssertNil(Base64Image.decode("data:text/plain,hello world hello world"))
    }

    func testImageFileBecomesDataURI() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "pop-base64-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        try pngData(width: 4, height: 4).write(to: file)
        let uri = try XCTUnwrap(Base64Image.dataURI(for: file))
        XCTAssertTrue(uri.hasPrefix("data:image/png;base64,iVBORw0KGgo"), String(uri.prefix(40)))
        XCTAssertEqual(Base64Image.decode(uri)?.width, 4)
        XCTAssertNil(Base64Image.dataURI(for: file, limit: 10))
    }

    @MainActor
    func testPluginShowsTheImage() async throws {
        let base64 = try pngData(width: 5, height: 3).base64EncodedString()
        let content = ContentClassifier.classify(.text(base64))
        XCTAssertTrue(Base64ImagePlugin().info.canHandle(content))
        let outcome = await Base64ImagePlugin().run(content, context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertNotNil(card.image)
        XCTAssertEqual(card.rows.map(\.value).prefix(2), ["PNG", "5 × 3"])
        XCTAssertEqual(card.buttons.map(\.title), ["复制图片", "存到「下载」", "贴到屏幕"])
    }
}
