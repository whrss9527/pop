import XCTest
@testable import Pop

final class CalculatorTests: XCTestCase {
    func testPrecedenceAndParentheses() {
        XCTAssertEqual(Calculator.evaluate("1+2*3"), 7)
        XCTAssertEqual(Calculator.evaluate("(1+2)*3"), 9)
        XCTAssertEqual(Calculator.evaluate("10 / 4"), 2.5)
        XCTAssertEqual(Calculator.evaluate("(3.5 - 1) / 2"), 1.25)
    }

    func testPowerIsRightAssociativeAndBindsTighterThanUnaryMinus() {
        XCTAssertEqual(Calculator.evaluate("2^3^2"), 512)
        XCTAssertEqual(Calculator.evaluate("-2^2"), -4)
        XCTAssertEqual(Calculator.evaluate("2^-1"), 0.5)
    }

    func testPercentAndFullWidthSymbols() {
        XCTAssertEqual(Calculator.evaluate("200*15%"), 30)
        XCTAssertEqual(Calculator.evaluate("3 × 4 ÷ 2"), 6)
        XCTAssertEqual(Calculator.evaluate("（1＋2）×3"), 9)
        XCTAssertEqual(Calculator.evaluate("1,000 + 2,500"), 3500)
        XCTAssertEqual(Calculator.evaluate("1+2="), 3)
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(Calculator.evaluate("1/0"))
        XCTAssertNil(Calculator.evaluate("1+"))
        XCTAssertNil(Calculator.evaluate("abc"))
        XCTAssertNil(Calculator.evaluate("(1+2"))
        XCTAssertNil(Calculator.evaluate(""))
        XCTAssertNil(Calculator.evaluate(String(repeating: "(", count: 200) + "1"))
    }

    func testFormatting() {
        XCTAssertEqual(Calculator.format(7), "7")
        XCTAssertEqual(Calculator.format(-3), "-3")
        XCTAssertEqual(Calculator.format(2.5), "2.5")
        XCTAssertEqual(Calculator.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(Calculator.format(1e20), "1e+20")
    }
}
