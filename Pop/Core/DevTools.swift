import Foundation

// 开发和链接相关的小工具的纯逻辑部分，方便测试。

// MARK: - 链接解析

/// 拆开链接的各个部分，去掉常见的跟踪参数。
enum LinkInspector {
    /// 常见的跟踪参数（去掉后打开的还是同一个页面）。utm_ 开头的另外判断。
    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_cid", "mc_eid", "yclid", "igshid",
        "_hsenc", "_hsmi", "mkt_tok", "spm", "scm", "vd_source", "share_source", "share_medium", "share_plat",
        "share_session_id", "share_tag", "share_from", "ref_src", "ref_url",
    ]

    /// 只在这些网站上当作跟踪参数的（别的网站上可能有用）
    static let siteTrackingParameters: [String: Set<String>] = [
        "youtube.com": ["si", "feature", "pp"],
        "youtu.be": ["si", "feature"],
        "spotify.com": ["si"],
        "twitter.com": ["s", "t"],
        "x.com": ["s", "t"],
        "bilibili.com": ["spm_id_from", "from_spmid", "unique_k", "buvid", "is_story_h5", "plat_id"],
        "instagram.com": ["igsh"],
    ]

    static func isTracking(_ name: String, host: String?) -> Bool {
        let lower = name.lowercased()
        if lower.hasPrefix("utm_") || trackingParameters.contains(lower) {
            return true
        }
        guard let host = host?.lowercased() else { return false }
        return siteTrackingParameters.contains { site, names in
            (host == site || host.hasSuffix("." + site)) && names.contains(lower)
        }
    }

    /// 去掉跟踪参数后的链接；没有可去掉的参数时返回 nil。留下的参数保持原来的编码（不会把 %2B 变回 +）
    static func cleaned(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems, !items.isEmpty else { return nil }
        let kept = items.filter { !isTracking($0.name.removingPercentEncoding ?? $0.name, host: components.host) }
        guard kept.count != items.count else { return nil }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url
    }

    /// 复制的内容只是一个带跟踪参数的网址时，返回去掉参数后的网址（「复制链接时去掉跟踪参数」用）
    static func cleanedLink(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 8192, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false, let cleaned = cleaned(url) else { return nil }
        return cleaned.absoluteString
    }

    /// 协议、主机、端口、路径、每个参数（解码后的值）、片段
    static func rows(for url: URL) -> [ResultCard.Row] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        var rows: [ResultCard.Row] = []
        if let scheme = components.scheme {
            rows.append(ResultCard.Row(label: String(localized: "协议"), value: scheme))
        }
        if let host = components.host, !host.isEmpty {
            rows.append(ResultCard.Row(label: String(localized: "主机"), value: host))
        }
        if let port = components.port {
            rows.append(ResultCard.Row(label: String(localized: "端口"), value: String(port)))
        }
        if !components.path.isEmpty, components.path != "/" {
            rows.append(ResultCard.Row(label: String(localized: "路径"), value: components.path))
        }
        for item in components.queryItems ?? [] {
            rows.append(ResultCard.Row(label: item.name, value: item.value ?? ""))
        }
        if let fragment = components.fragment, !fragment.isEmpty {
            rows.append(ResultCard.Row(label: String(localized: "片段"), value: fragment))
        }
        return rows
    }
}

// MARK: - JWT

/// 解码 JWT（只解码，不验证签名）
enum JWTDecoder {
    /// 三段 base64url，用点分开，第一段是 {" 开头的 JSON
    static let pattern = #"^eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$"#

    struct Token {
        var header: String
        var payload: String
        var claims: [String: Any]
        var algorithm: String?
    }

    static func decode(_ text: String) -> Token? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = base64URLDecode(String(parts[0])), let payloadData = base64URLDecode(String(parts[1])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { return nil }
        return Token(header: prettyJSON(header), payload: prettyJSON(claims), claims: claims, algorithm: header["alg"] as? String)
    }

    static func base64URLDecode(_ segment: String) -> Data? {
        var base64 = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 {
            return nil
        }
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private static func prettyJSON(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    /// 常用声明：算法、签发者、主题、受众、签发时间、生效时间、过期时间（带是否过期）
    static func rows(for token: Token, now: Date = Date(), timeZone: TimeZone = .current) -> [ResultCard.Row] {
        var rows: [ResultCard.Row] = []
        if let algorithm = token.algorithm {
            rows.append(ResultCard.Row(label: String(localized: "算法"), value: algorithm))
        }
        for (key, label) in [("iss", String(localized: "签发者")), ("sub", String(localized: "主题"))] {
            if let value = token.claims[key] {
                rows.append(ResultCard.Row(label: label, value: "\(value)"))
            }
        }
        if let audience = token.claims["aud"] {
            let value = (audience as? [Any])?.map { "\($0)" }.joined(separator: ", ") ?? "\(audience)"
            rows.append(ResultCard.Row(label: String(localized: "受众"), value: value))
        }
        for (key, label) in [("iat", String(localized: "签发时间")), ("nbf", String(localized: "生效时间")), ("exp", String(localized: "过期时间"))] {
            guard let seconds = (token.claims[key] as? NSNumber)?.doubleValue else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            var value = TimestampConverter.localString(date, timeZone: timeZone)
            if key == "exp" {
                value += date < now ? String(localized: "（已过期）") : String(localized: "（\(relative(date, now: now))过期）")
            }
            rows.append(ResultCard.Row(label: label, value: value))
        }
        return rows
    }

    private static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Localization.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
