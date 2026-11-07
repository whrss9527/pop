import Foundation

/// SemVer 2.0 的严格解析与优先级比较；数字保留为字符串，不受整数位数限制。
struct SemanticVersion: Equatable, Sendable {
    static let maximumLength = 32_000

    let rawValue: String
    private let release: [String]
    private let prerelease: [String]

    init?(_ text: String) {
        guard !text.isEmpty, text.utf8.count <= Self.maximumLength else { return nil }
        let buildParts = text.split(separator: "+", omittingEmptySubsequences: false)
        guard buildParts.count <= 2,
              buildParts.count == 1 || Self.identifiers(buildParts[1], numericLeadingZeroAllowed: true) != nil else {
            return nil
        }
        let version = buildParts[0]
        let releaseText: Substring
        let prerelease: [String]
        if let separator = version.firstIndex(of: "-") {
            releaseText = version[..<separator]
            guard let identifiers = Self.identifiers(version[version.index(after: separator)...],
                                                     numericLeadingZeroAllowed: false) else { return nil }
            prerelease = identifiers
        } else {
            releaseText = version
            prerelease = []
        }
        let release = releaseText.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard release.count == 3, release.allSatisfy(Self.isReleaseNumber) else { return nil }
        self.rawValue = text
        self.release = release
        self.prerelease = prerelease
    }

    /// 构建信息不参与比较；相同优先级并不表示原始版本文字相同。
    func comparePrecedence(to other: Self) -> ComparisonResult {
        for (left, right) in zip(release, other.release) {
            let result = Self.compareNumbers(left, right)
            if result != .orderedSame { return result }
        }
        if prerelease.isEmpty || other.prerelease.isEmpty {
            if prerelease.isEmpty == other.prerelease.isEmpty { return .orderedSame }
            return prerelease.isEmpty ? .orderedDescending : .orderedAscending
        }
        for (left, right) in zip(prerelease, other.prerelease) where left != right {
            let leftNumeric = Self.isNumeric(left)
            let rightNumeric = Self.isNumeric(right)
            if leftNumeric && rightNumeric { return Self.compareNumbers(left, right) }
            if leftNumeric != rightNumeric { return leftNumeric ? .orderedAscending : .orderedDescending }
            // 标识符只允许 ASCII，Swift 字典顺序在这里就是 SemVer 要求的 ASCII 顺序。
            return left < right ? .orderedAscending : .orderedDescending
        }
        if prerelease.count == other.prerelease.count { return .orderedSame }
        return prerelease.count < other.prerelease.count ? .orderedAscending : .orderedDescending
    }

    private static func identifiers(_ text: Substring, numericLeadingZeroAllowed: Bool) -> [String]? {
        let identifiers = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard identifiers.allSatisfy({ value in
            !value.isEmpty && value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45
            } && (numericLeadingZeroAllowed || !Self.isNumeric(value) || Self.isReleaseNumber(value))
        }) else { return nil }
        return identifiers
    }

    private static func isNumeric(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isReleaseNumber(_ value: String) -> Bool {
        isNumeric(value) && (value == "0" || value.first != "0")
    }

    private static func compareNumbers(_ left: String, _ right: String) -> ComparisonResult {
        if left.count != right.count { return left.count < right.count ? .orderedAscending : .orderedDescending }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }
}

/// 每行一个版本；仅忽略空行并归一化 CRLF，不替用户修正版本或去掉行首尾空白。
struct SemanticVersionList: Sendable {
    static let maximumTextLength = SemanticVersion.maximumLength
    static let maximumVersions = 200

    enum ParseError: Error, Equatable, Sendable {
        case tooLong
        case tooFewVersions
        case tooManyVersions
        case invalidVersion(line: Int)
    }

    let versions: [SemanticVersion]

    static func parse(_ text: String) throws -> Self {
        guard text.utf8.count <= maximumTextLength else { throw ParseError.tooLong }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var versions: [SemanticVersion] = []
        for (offset, line) in lines.enumerated() where !line.isEmpty {
            guard versions.count < maximumVersions else { throw ParseError.tooManyVersions }
            guard let version = SemanticVersion(line) else { throw ParseError.invalidVersion(line: offset + 1) }
            versions.append(version)
        }
        guard versions.count >= 2 else { throw ParseError.tooFewVersions }
        return Self(versions: versions)
    }

    /// 使用原位置打破优先级相同的平局，升序与降序均保留原有顺序和构建信息。
    func sorted(descending: Bool = false) -> [String] {
        versions.enumerated().sorted { left, right in
            let comparison = left.element.comparePrecedence(to: right.element)
            if comparison == .orderedSame { return left.offset < right.offset }
            return comparison == (descending ? .orderedDescending : .orderedAscending)
        }.map { $0.element.rawValue }
    }
}
