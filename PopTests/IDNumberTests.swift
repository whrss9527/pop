import XCTest
@testable import Pop

final class IDNumberTests: XCTestCase {
    private let today = IDNumber.calendar.date(from: DateComponents(year: 2026, month: 9, day: 30)) ?? Date()

    private func value(_ info: IDNumber.Info?, _ label: String) -> String? {
        info?.rows.first { $0.label == label }?.value
    }

    func testResidentID() throws {
        // 国家标准里的示例号码
        let info = try XCTUnwrap(IDNumber.parse("11010519491231002X", today: today))
        XCTAssertEqual(info.kind, .residentID)
        XCTAssertTrue(info.isValid)
        XCTAssertEqual(value(info, "校验"), "通过")
        XCTAssertEqual(value(info, "出生日期"), "1949 年 12 月 31 日")
        XCTAssertEqual(value(info, "年龄"), "76 岁")
        XCTAssertEqual(value(info, "性别"), "女")
        XCTAssertEqual(value(info, "地区"), "北京（110105）")

        // 小写 x、空格、全角数字都认得
        XCTAssertEqual(IDNumber.parse("110105 19491231 002x", today: today)?.isValid, true)
        XCTAssertEqual(IDNumber.parse("１１０１０５１９４９１２３１００２Ｘ", today: today)?.number, "11010519491231002X")

        let old = try XCTUnwrap(IDNumber.parse("440524188001010014", today: today))
        XCTAssertTrue(old.isValid)
        XCTAssertEqual(value(old, "性别"), "男")
        XCTAssertEqual(value(old, "年龄"), "146 岁")
        XCTAssertEqual(value(old, "地区"), "广东（440524）")

        // 最后一位错了：告诉应该是什么
        let wrong = try XCTUnwrap(IDNumber.parse("110105194912310021", today: today))
        XCTAssertEqual(wrong.kind, .residentID)
        XCTAssertFalse(wrong.isValid)
        XCTAssertEqual(wrong.expectedCheck, "X")
        XCTAssertTrue(IDNumber.card(wrong).body.contains("应该是 X"), IDNumber.card(wrong).body)

        // 2001 年没有 2 月 29 日，不是身份证号
        XCTAssertNotEqual(IDNumber.parse("440304200102290011", today: today)?.kind, .residentID)

        let permit = try XCTUnwrap(IDNumber.parse("810000199505200123", today: today))
        XCTAssertEqual(permit.kind, .residencePermit)
        XCTAssertTrue(permit.isValid)
        XCTAssertEqual(value(permit, "地区"), "香港（810000）")
    }

    func testOldResidentIDGetsEighteenDigits() throws {
        let info = try XCTUnwrap(IDNumber.parse("110105491231002", today: today))
        XCTAssertEqual(info.kind, .oldResidentID)
        XCTAssertEqual(value(info, "18 位号码"), "11010519491231002X")
        XCTAssertEqual(value(info, "出生日期"), "1949 年 12 月 31 日")
        XCTAssertEqual(value(info, "性别"), "女")
        XCTAssertTrue(IDNumber.card(info).body.contains("18 位"))
    }

    func testCreditCode() throws {
        let company = try XCTUnwrap(IDNumber.parse("91350100M00010012Y"))
        XCTAssertEqual(company.kind, .creditCode)
        XCTAssertTrue(company.isValid)
        XCTAssertEqual(value(company, "登记管理部门"), "市场监管（工商）")
        XCTAssertEqual(value(company, "机构类别"), "企业")
        XCTAssertEqual(value(company, "登记地"), "福建（350100）")
        XCTAssertEqual(value(company, "组织机构代码"), "M0001001-2")

        // 全是数字的代码：校验通过就按信用代码算，不当成银行卡号
        let society = try XCTUnwrap(IDNumber.parse("521100005000189238"))
        XCTAssertEqual(society.kind, .creditCode)
        XCTAssertEqual(value(society, "登记管理部门"), "民政")
        XCTAssertEqual(value(society, "机构类别"), "民办非企业单位")

        let central = try XCTUnwrap(IDNumber.parse("12100000400000678Y"))
        XCTAssertEqual(value(central, "机构类别"), "事业单位")
        XCTAssertNil(value(central, "登记地"))

        let wrong = try XCTUnwrap(IDNumber.parse("91350100M00010012A"))
        XCTAssertEqual(wrong.kind, .creditCode)
        XCTAssertFalse(wrong.isValid)
        XCTAssertEqual(wrong.expectedCheck, "Y")
    }

    func testBankCard() throws {
        let unionPay = try XCTUnwrap(IDNumber.parse("6222 0212 3456 7890 128"))
        XCTAssertEqual(unionPay.kind, .bankCard)
        XCTAssertTrue(unionPay.isValid)
        XCTAssertEqual(value(unionPay, "卡组织"), "银联")
        XCTAssertEqual(value(unionPay, "位数"), "19 位")
        XCTAssertEqual(value(unionPay, "分组"), "6222 0212 3456 7890 128")
        // 18 位的卡号不会被当成信用代码
        XCTAssertEqual(IDNumber.parse("622202123456789012")?.kind, .bankCard)

        XCTAssertEqual(IDNumber.parse("4111111111111111")?.isValid, true)
        XCTAssertEqual(value(IDNumber.parse("4111111111111111"), "卡组织"), "Visa")
        let typo = try XCTUnwrap(IDNumber.parse("4111-1111-1111-1112"))
        XCTAssertFalse(typo.isValid)
        XCTAssertNil(typo.expectedCheck)
        XCTAssertEqual(IDNumber.parse("440304200102290011")?.kind, .bankCard)
    }

    func testIgnoresOtherText() {
        for text in ["hello", "12345", "2026-09-30", "13812345678", "11010519491231002X 和 91350100M00010012Y", "1234567890123"] {
            XCTAssertNil(IDNumber.parse(text), text)
        }
    }

    @MainActor
    func testPluginAndCard() async throws {
        let plugin = IDNumberPlugin()
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.text("11010519491231002X"))))
        XCTAssertTrue(plugin.info.canHandle(ContentClassifier.classify(.text("6222021234567890128"))))
        XCTAssertFalse(plugin.info.canHandle(ContentClassifier.classify(.text("你好"))))
        let outcome = await plugin.run(ContentClassifier.classify(.text("91350100M00010012Y")),
                                       context: PluginContext(settings: AppSettings(), openSettings: {}))
        guard case .card(let card) = outcome else { return XCTFail("应该返回结果卡片") }
        XCTAssertEqual(card.title, "统一社会信用代码")
        XCTAssertEqual(card.body, "校验通过")
        let copy = try XCTUnwrap(card.copyText)
        XCTAssertTrue(copy.hasPrefix("统一社会信用代码：91350100M00010012Y\n"), copy)
        XCTAssertTrue(copy.contains("机构类别：企业"), copy)
    }
}
