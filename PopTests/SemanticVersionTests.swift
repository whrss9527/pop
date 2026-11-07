import Foundation
import XCTest
@testable import Pop

final class SemanticVersionTests: XCTestCase {
    private func version(_ text: String, file: StaticString = #filePath, line: UInt = #line) throws -> SemanticVersion {
        try XCTUnwrap(SemanticVersion(text), text, file: file, line: line)
    }

    func testOfficialPrecedenceSequence() throws {
        let sequence = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
                        "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        for pair in zip(sequence, sequence.dropFirst()) {
            XCTAssertEqual(try version(pair.0).comparePrecedence(to: version(pair.1)), .orderedAscending)
            XCTAssertEqual(try version(pair.1).comparePrecedence(to: version(pair.0)), .orderedDescending)
        }
    }

    func testReleaseComponentsAreNumericWithoutIntegerOverflow() throws {
        for pair in [("1.9.0", "1.10.0"), ("1.0.99", "1.1.0"), ("99.0.0", "100.0.0"),
                     ("18446744073709551615.0.0", "18446744073709551616.0.0"),
                     ("1." + String(repeating: "9", count: 200) + ".0", "1.1" + String(repeating: "0", count: 200) + ".0")] {
            XCTAssertEqual(try version(pair.0).comparePrecedence(to: version(pair.1)), .orderedAscending)
        }
    }

    func testPrereleaseNumbersDoNotOverflowAndSortBeforeText() throws {
        let smaller = "1.0.0-" + String(repeating: "9", count: 1000)
        let bigger = "1.0.0-1" + String(repeating: "0", count: 1000)
        XCTAssertEqual(try version(smaller).comparePrecedence(to: version(bigger)), .orderedAscending)
        XCTAssertEqual(try version(bigger).comparePrecedence(to: version("1.0.0-alpha")), .orderedAscending)
        XCTAssertEqual(try version("1.0.0-2").comparePrecedence(to: version("1.0.0-10")), .orderedAscending)
    }

    func testNonNumericPrereleaseUsesASCIIOrderingAndPrefixLength() throws {
        for pair in [("1.0.0-A", "1.0.0-a"), ("1.0.0-a-2", "1.0.0-a-10"),
                     ("1.0.0-alpha", "1.0.0-alpha.0"), ("1.0.0-alpha.0", "1.0.0-alpha.0.beta")] {
            let expected: ComparisonResult = pair.0 == "1.0.0-a-2" ? .orderedDescending : .orderedAscending
            XCTAssertEqual(try version(pair.0).comparePrecedence(to: version(pair.1)), expected)
        }
    }

    func testBuildMetadataDoesNotAffectPrecedenceOrChangeRawValues() throws {
        let first = try version("1.2.3-beta+001.build-Z")
        let second = try version("1.2.3-beta+002")
        XCTAssertEqual(first.comparePrecedence(to: second), .orderedSame)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.rawValue, "1.2.3-beta+001.build-Z")
        XCTAssertEqual(try version("1.2.3").comparePrecedence(to: version("1.2.3+001")), .orderedSame)
    }

    func testStrictParserRejectsMalformedAndNonASCIIInputs() {
        let invalid = ["", "1", "1.2", "1.2.3.4", "v1.2.3", "V1.2.3", "01.2.3", "1.02.3", "1.2.03",
                       "-1.2.3", "+1.2.3", "1.2.3-", "1.2.3+", "1.2.3-alpha..beta", "1.2.3+.a",
                       "1.2.3+a..b", "1.2.3+build+second", "1.2.3-01", "1.2.3-alpha.00", "1.2.3-a_b",
                       "1.2.3+a_b", " 1.2.3", "1.2.3 ", "1.2.3\n", "1.2.3\t", "１.2.3", "1.2.3-β",
                       "1.2.3-١", "1.2.3\0", "1.2.3-\u{200B}alpha"]
        for input in invalid { XCTAssertNil(SemanticVersion(input), input) }
    }

    func testValidIdentifiersIncludeHyphensAndLeadingZerosOnlyInBuildMetadata() throws {
        for input in ["0.0.0", "1.2.3-0", "1.2.3-0A", "1.2.3--", "1.2.3-alpha-1.2a", "1.2.3+001.02", "1.2.3+--"] {
            XCTAssertEqual(try version(input).rawValue, input)
        }
    }

    func testListSupportsCRLFEmptyLinesAndFinalNewline() throws {
        let list = try SemanticVersionList.parse("\r\n2.0.0\r\n\r\n1.0.0\r\n")
        XCTAssertEqual(list.versions.map(\.rawValue), ["2.0.0", "1.0.0"])
        XCTAssertEqual(list.sorted(), ["1.0.0", "2.0.0"])
    }

    func testWhitespaceAndBareCRDoNotSilentlyNormalizeVersions() {
        for text in ["1.0.0\n 2.0.0", "1.0.0\n2.0.0 ", "1.0.0\n\t\n2.0.0", "1.0.0\r2.0.0"] {
            XCTAssertThrowsError(try SemanticVersionList.parse(text))
        }
    }

    func testInvalidVersionReportsPhysicalLineWithoutContent() {
        XCTAssertThrowsError(try SemanticVersionList.parse("\n1.0.0\n\nv2.0.0\n")) { error in
            XCTAssertEqual(error as? SemanticVersionList.ParseError, .invalidVersion(line: 4))
        }
    }

    func testAscendingAndDescendingFollowVersionPrecedence() throws {
        let list = try SemanticVersionList.parse("2.0.0\n1.10.0\n1.9.0\n2.0.0-rc.1")
        XCTAssertEqual(list.sorted(), ["1.9.0", "1.10.0", "2.0.0-rc.1", "2.0.0"])
        XCTAssertEqual(list.sorted(descending: true), ["2.0.0", "2.0.0-rc.1", "1.10.0", "1.9.0"])
    }

    func testEqualPrecedenceKeepsOriginalOrderAndDuplicatesBothDirections() throws {
        let equal = ["1.0.0+z", "1.0.0", "1.0.0+a", "1.0.0+z"]
        let list = try SemanticVersionList.parse((["2.0.0"] + equal + ["0.0.0"]).joined(separator: "\n"))
        XCTAssertEqual(list.sorted(), ["0.0.0"] + equal + ["2.0.0"])
        XCTAssertEqual(list.sorted(descending: true), ["2.0.0"] + equal + ["0.0.0"])
    }

    func testMinimumAndMaximumVersionCountsAreAccepted() throws {
        XCTAssertEqual(try SemanticVersionList.parse("1.0.0\n2.0.0").versions.count, 2)
        let lines = (0..<SemanticVersionList.maximumVersions).map { "1.0.0+\($0)" }
        let list = try SemanticVersionList.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(list.versions.count, 200)
        XCTAssertEqual(list.sorted(), lines)
        XCTAssertEqual(list.sorted(descending: true), lines)
    }

    func testVersionCountBeyondLimitIsRejected() {
        let text = Array(repeating: "1.0.0", count: 201).joined(separator: "\n")
        XCTAssertThrowsError(try SemanticVersionList.parse(text)) { error in
            XCTAssertEqual(error as? SemanticVersionList.ParseError, .tooManyVersions)
        }
    }

    func testFewerThanTwoNonemptyVersionsIsRejected() {
        for text in ["", "\n\n", "1.0.0", "\n1.0.0\n"] {
            XCTAssertThrowsError(try SemanticVersionList.parse(text)) { error in
                XCTAssertEqual(error as? SemanticVersionList.ParseError, .tooFewVersions)
            }
        }
    }

    func testInputByteLimitIsInclusiveAndEnforcedBeforeParsing() throws {
        let prefix = "1.0.0+"
        let suffix = "\n1.0.1"
        let text = prefix + String(repeating: "a", count: SemanticVersionList.maximumTextLength - prefix.utf8.count - suffix.utf8.count) + suffix
        XCTAssertEqual(text.utf8.count, SemanticVersionList.maximumTextLength)
        XCTAssertEqual(try SemanticVersionList.parse(text).versions.count, 2)
        XCTAssertThrowsError(try SemanticVersionList.parse(text + "a")) { error in
            XCTAssertEqual(error as? SemanticVersionList.ParseError, .tooLong)
        }
        XCTAssertNil(SemanticVersion(String(repeating: "1", count: SemanticVersion.maximumLength + 1)))
    }
}
