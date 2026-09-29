import XCTest
@testable import Pop

final class UnitConverterTests: XCTestCase {
    private func convert(_ text: String, to id: String) -> Double? {
        guard let quantity = UnitConverter.parse(text), let unit = UnitConverter.unit(id: id) else { return nil }
        return UnitConverter.convert(quantity, to: unit)
    }

    func testParsing() {
        XCTAssertEqual(UnitConverter.parse("5 km")?.unit.id, "km")
        XCTAssertEqual(UnitConverter.parse("5km")?.value, 5)
        XCTAssertEqual(UnitConverter.parse("1,500 m")?.value, 1500)
        XCTAssertEqual(UnitConverter.parse("100°F")?.unit.id, "F")
        XCTAssertEqual(UnitConverter.parse("37.5 ℃")?.unit.id, "C")
        XCTAssertEqual(UnitConverter.parse("-5 °C")?.value, -5)
        XCTAssertEqual(UnitConverter.parse("2 斤")?.unit.id, "jin")
        XCTAssertEqual(UnitConverter.parse("3亩")?.unit.id, "mu")
        XCTAssertEqual(UnitConverter.parse("27\"")?.unit.id, "in")
        XCTAssertEqual(UnitConverter.parse("100 km / h")?.unit.id, "kmh")
        XCTAssertEqual(UnitConverter.parse("16GB")?.unit.id, "GB")
        XCTAssertEqual(UnitConverter.parse("500 mb")?.unit.id, "MB")
        XCTAssertEqual(UnitConverter.parse("100Mb")?.unit.id, "Mb")
        XCTAssertEqual(UnitConverter.parse("100 Mbps")?.unit.id, "Mbps")
        XCTAssertEqual(UnitConverter.parse("20 MB/s")?.unit.id, "MBps")
        XCTAssertEqual(UnitConverter.parse("2 fl oz")?.unit.id, "floz")
        XCTAssertEqual(UnitConverter.parse("10 m")?.unit.id, "m")
        let height = UnitConverter.parse("5'11\"")
        XCTAssertEqual(height?.unit.id, "ft")
        XCTAssertEqual(height?.value ?? 0, 5 + 11.0 / 12, accuracy: 1e-9)
        // 不是带单位的数值：单独的数字、有歧义的单个大写字母、负的长度、不认识的单位
        for text in ["12345", "3.14", "5G", "16G", "100M", "10T", "-5 km", "5 min", "50%", "3 in 1", "hello", "12 pt", ""] {
            XCTAssertNil(UnitConverter.parse(text), text)
        }
    }

    func testConversions() throws {
        XCTAssertEqual(try XCTUnwrap(convert("5 km", to: "mi")), 3.106_855_96, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(convert("100°F", to: "C")), 37.777_777_8, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(convert("0 °C", to: "K")), 273.15, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(convert("300 kelvin", to: "F")), 80.33, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(convert("2 斤", to: "kg")), 1, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(convert("1 亩", to: "m2")), 666.666_666_7, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(convert("100 Mbps", to: "MBps")), 12.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(convert("1 TB", to: "GiB")), 931.322_574_6, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(convert("60 mph", to: "kmh")), 96.560_64, accuracy: 1e-6)
        let km = try XCTUnwrap(UnitConverter.parse("5 km"))
        XCTAssertNil(UnitConverter.convert(km, to: try XCTUnwrap(UnitConverter.unit(id: "kg"))))
    }

    func testRowsAndFormatting() throws {
        XCTAssertEqual(UnitConverter.format(3.106_855_961), "3.10686")
        XCTAssertEqual(UnitConverter.format(16_404.199_475), "16,404.2")
        XCTAssertEqual(UnitConverter.format(5000), "5,000")
        XCTAssertEqual(UnitConverter.format(-0.000_000_000_000_1), "0")

        let rows = UnitConverter.rows(for: try XCTUnwrap(UnitConverter.parse("5 km")))
        XCTAssertEqual(rows.first { $0.label == "英里" }?.value, "3.10686 mi")
        XCTAssertEqual(rows.first { $0.label == "米" }?.value, "5,000 m")
        // 不列出原来的单位，也不列太大、不好读的数
        XCTAssertNil(rows.first { $0.label == "千米" })
        XCTAssertNil(rows.first { $0.label == "毫米" })
        XCTAssertLessThanOrEqual(rows.count, 9)

        let temperature = UnitConverter.rows(for: try XCTUnwrap(UnitConverter.parse("100°F")))
        XCTAssertEqual(temperature.map(\.label), ["摄氏度", "开尔文"])
        XCTAssertEqual(temperature.first?.value, "37.7778°C")

        let weight = UnitConverter.rows(for: try XCTUnwrap(UnitConverter.parse("1 kg")))
        XCTAssertEqual(weight.first { $0.label == "斤" }?.value, "2斤")
        XCTAssertEqual(weight.first { $0.label == "磅" }?.value, "2.20462 lb")

        let height = UnitConverter.rows(for: try XCTUnwrap(UnitConverter.parse("180 cm")))
        XCTAssertEqual(height.first { $0.label == "英尺英寸" }?.value, "5' 10.9\"")
        XCTAssertEqual(UnitConverter.feetAndInches(meters: 1.8288), "6' 0\"")
    }
}
