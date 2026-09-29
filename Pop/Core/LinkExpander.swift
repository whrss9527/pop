import Foundation

/// 展开短链接：一步一步跟着跳转，看最后到了哪个网址。只在用户点「展开短链接」时才访问网络。
enum LinkExpander {
    /// 常见的短链接服务
    static let shortHosts: Set<String> = [
        "bit.ly", "t.co", "tinyurl.com", "goo.gl", "is.gd", "ow.ly", "buff.ly", "rebrand.ly", "cutt.ly", "shorturl.at",
        "tiny.cc", "lnkd.in", "s.id", "rb.gy", "amzn.to", "a.co", "fb.me", "spoti.fi", "apple.co", "aka.ms", "g.co",
        "t.cn", "dwz.cn", "url.cn", "suo.im", "mrw.so", "sourl.cn", "b23.tv", "v.douyin.com", "xhslink.com", "reurl.cc",
    ]

    static func isShortLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              var host = url.host()?.lowercased() else { return false }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return shortHosts.contains(host)
    }

    struct Expansion: Equatable {
        var final: URL
        /// 依次跳到的网址（最后一个就是 final）
        var hops: [URL]
    }

    enum Failure: Error {
        case tooManyRedirects
    }

    static func expand(_ url: URL, session: URLSession = .shared, limit: Int = 10) async throws -> Expansion {
        var current = url
        var hops: [URL] = []
        for _ in 0..<limit {
            guard let next = try await redirect(from: current, session: session) else {
                return Expansion(final: current, hops: hops)
            }
            hops.append(next)
            current = next
        }
        throw Failure.tooManyRedirects
    }

    /// 访问一次（不自动跳转），返回要跳去的地址；不跳转时返回 nil
    private static func redirect(from url: URL, session: URLSession) async throws -> URL? {
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: url, timeoutInterval: 10)
            request.httpMethod = method
            if method == "GET" {
                request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            }
            let (_, response) = try await session.data(for: request, delegate: NoAutomaticRedirect())
            guard let http = response as? HTTPURLResponse else { return nil }
            if (300...399).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location") {
                return URL(string: location, relativeTo: url)?.absoluteURL
            }
            // 有的短链接服务不接受 HEAD，换 GET 再问一次
            if method == "HEAD", [400, 403, 405, 501].contains(http.statusCode) {
                continue
            }
            return nil
        }
        return nil
    }

    static func describe(_ error: Error) -> String {
        if case Failure.tooManyRedirects = error {
            return "跳转次数太多"
        }
        return error.localizedDescription
    }

    /// 展开后的卡片：最后的网址（去掉跟踪参数），中间每一跳
    static func card(for expansion: Expansion) -> ResultCard {
        let final = expansion.final
        let clean = LinkInspector.cleaned(final) ?? final
        var detail = expansion.hops.isEmpty ? "这个链接没有跳转" : "跳转了 \(expansion.hops.count) 次"
        if clean != final {
            detail += "，已去掉跟踪参数"
        }
        let rows = expansion.hops.enumerated().map { index, hop in
            ResultCard.Row(label: "第 \(index + 1) 跳", value: hop.absoluteString)
        }
        return ResultCard(title: "展开短链接", body: clean.absoluteString, detail: detail, monospaced: true,
                          copyText: clean.absoluteString, replaceText: clean.absoluteString, rows: rows, rowLineLimit: 2,
                          buttons: [CardButton(title: "打开链接", action: .open(clean))])
    }
}

/// 不让 URLSession 自己跟着跳转，这样才能拿到每一跳的地址
private final class NoAutomaticRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
