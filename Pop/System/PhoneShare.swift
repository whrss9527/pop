import AppKit
import Network
import SystemConfiguration
import UniformTypeIdentifiers

// MARK: - 本机在局域网里的地址

enum LANAddress {
    struct Interface: Equatable {
        var name: String
        var address: String
    }

    /// 已经连上的网卡的 IPv4 地址（不含回环地址）
    static func interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [Interface] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(bitPattern: entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let capacity = Int(NI_MAXHOST)
            var host = [CChar](repeating: 0, count: capacity)
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(capacity),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = host.withUnsafeBufferPointer { buffer in
                buffer.baseAddress.map { String(cString: $0) } ?? ""
            }
            result.append(Interface(name: String(cString: entry.pointee.ifa_name), address: text))
        }
        return result
    }

    /// 手机能打开的地址，最可能的排在前面：Wi-Fi 和有线网卡（en…）、互联网共享（bridge…）上的私有地址。
    /// VPN、虚拟机这类网卡和自动分配的 169.254 地址手机访问不到，不要
    static func candidates(_ list: [Interface] = interfaces()) -> [String] {
        var ranked: [(address: String, rank: Int, order: Int)] = []
        for (order, item) in list.enumerated() {
            let physical = item.name.hasPrefix("en")
            guard physical || item.name.hasPrefix("bridge"), !item.address.hasPrefix("169.254."),
                  !ranked.contains(where: { $0.address == item.address }) else { continue }
            var rank = isPrivate(item.address) ? 0 : 10
            if item.name == "en0" {
                rank -= 2
            } else if physical {
                rank -= 1
            }
            ranked.append((address: item.address, rank: rank, order: order))
        }
        return ranked.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }.map { $0.address }
    }

    /// 10.x、172.16–31.x、192.168.x
    static func isPrivate(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 192 && parts[1] == 168)
    }

    /// 「系统设置 → 通用 → 共享」里的电脑名称
    static func computerName() -> String {
        guard let name = SCDynamicStoreCopyComputerName(nil, nil) else { return "Mac" }
        return name as String
    }
}

// MARK: - HTTP 请求

/// 一个 HTTP 请求的请求行和头部
struct HTTPRequestHead: Equatable {
    var method: String
    /// 路径（已经解码，不含 ? 后面的部分）
    var path: String
    var query: [String: String]
    /// 头部，名字都是小写
    var headers: [String: String]

    init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/"), let components = URLComponents(string: String(parts[1])) else { return nil }
        method = parts[0].uppercased()
        path = components.path
        query = (components.queryItems ?? []).reduce(into: [:]) { result, item in
            result[item.name] = item.value ?? ""
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        self.headers = headers
    }

    var contentLength: Int? {
        headers["content-length"].flatMap { Int($0) }.flatMap { $0 >= 0 ? $0 : nil }
    }
}

/// 网页上的几个地址。都在 /口令/ 下面，口令不对一律 404
enum LANShareRoute: Equatable {
    /// 网页
    case page
    /// 下载第几个文件；inline 是在网页里预览（图片缩略图）
    case file(index: Int, inline: Bool)
    /// 手机传文件过来
    case upload(name: String)
    case notFound

    static func resolve(_ request: HTTPRequestHead, token: String, fileCount: Int) -> LANShareRoute {
        let parts = request.path.split(separator: "/").map(String.init)
        guard parts.first == token else { return .notFound }
        let rest = Array(parts.dropFirst())
        if rest.isEmpty {
            return request.method == "GET" ? .page : .notFound
        }
        if rest.count == 2, rest[0] == "f", request.method == "GET" {
            guard let index = Int(rest[1]), (0..<fileCount).contains(index) else { return .notFound }
            return .file(index: index, inline: request.query["view"] == "1")
        }
        if rest == ["u"], request.method == "PUT" || request.method == "POST" {
            return .upload(name: request.query["name"] ?? "")
        }
        return .notFound
    }
}

// MARK: - 网页

enum LANSharePage {
    struct Item: Equatable {
        var index: Int
        var name: String
        var size: Int64
        /// 在网页上显示缩略图
        var preview: Bool
    }

    /// 手机浏览器能直接显示的图片才放缩略图
    static let previewExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "heic", "heif"]

    static func item(index: Int, url: URL, name: String) -> Item {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let preview = previewExtensions.contains((name as NSString).pathExtension.lowercased()) && size < 15_000_000
        return Item(index: index, name: name, size: size, preview: preview)
    }

    static func html(token: String, items: [Item], text: String? = nil, computerName: String) -> String {
        let base = "/\(token)"
        let rows = items.enumerated().map { position, item -> String in
            let link = "\(base)/f/\(item.index)"
            // 太多图片时后面的不放缩略图，免得手机一下子下载太多
            // 点缩略图打开大图：手机上长按就能存到相册
            let thumbnail = item.preview && position < 30
                ? "<a href=\"\(link)?view=1\"><img src=\"\(link)?view=1\" alt=\"\" loading=\"lazy\" onerror=\"this.remove()\"></a>"
                : "<span class=\"icon\">📄</span>"
            return "<li>\(thumbnail)<div class=\"info\"><span class=\"name\">\(escape(item.name))</span><span class=\"size\">\(sizeLabel(item.size))</span></div><a class=\"button\" href=\"\(link)\" download>\(escape(String(localized: "下载")))</a></li>"
        }.joined(separator: "\n")
        var shared = ""
        if let text, !text.isEmpty {
            // 纯 http 的网页用不了剪贴板接口：放在文本框里，点一下全选，长按拷贝
            let lineCount = min(max(text.split(separator: "\n", omittingEmptySubsequences: false).count, 2), 10)
            let link = URL(string: text).flatMap { $0.scheme == "http" || $0.scheme == "https" ? $0 : nil }
            shared = "<section><h2>\(escape(String(localized: "文字")))</h2><textarea readonly rows=\"\(lineCount)\" onfocus=\"this.select()\">\(escape(text))</textarea>"
                + (link.map { "<p><a class=\"button\" href=\"\(escape($0.absoluteString))\">\(escape(String(localized: "打开链接")))</a></p>" } ?? "")
                + "<p class=\"hint\">\(escape(String(localized: "点一下全选，再长按拷贝")))</p></section>"
        }
        let photoHint = items.contains(where: \.preview) ? "<p class=\"hint\">\(escape(String(localized: "照片：点缩略图打开大图，长按存到相册")))</p>" : ""
        let downloads = items.isEmpty ? "" : """
        <section>
        <h2>\(escape(String(localized: "存到手机")))</h2>
        <ul>
        \(rows)
        </ul>
        \(photoHint)
        </section>
        """
        return #"""
        <!doctype html>
        <html lang="\#(Localization.isChinese ? "zh-CN" : "en")">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Pop · \#(escape(String(localized: "传到手机")))</title>
        <style>
        :root { color-scheme: light dark; --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --accent: #0a84ff; --line: rgba(0,0,0,0.08); }
        @media (prefers-color-scheme: dark) { :root { --bg: #000000; --card: #1c1c1e; --text: #f5f5f7; --muted: #98989d; --line: rgba(255,255,255,0.1); } }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 20px 16px 40px; background: var(--bg); color: var(--text); font: 16px/1.5 -apple-system, BlinkMacSystemFont, "PingFang SC", "Noto Sans CJK SC", sans-serif; }
        main { max-width: 560px; margin: 0 auto; }
        h1 { font-size: 22px; margin: 4px 0 2px; }
        .from { color: var(--muted); font-size: 14px; margin: 0 0 20px; }
        section { background: var(--card); border-radius: 16px; padding: 16px; margin-bottom: 16px; }
        h2 { font-size: 15px; margin: 0 0 10px; color: var(--muted); font-weight: 600; }
        ul { list-style: none; margin: 0; padding: 0; }
        li { display: flex; align-items: center; gap: 12px; padding: 10px 0; border-top: 1px solid var(--line); }
        li:first-child { border-top: none; }
        li a:has(img) { flex: none; display: flex; }
        li img, .icon { width: 52px; height: 52px; border-radius: 10px; object-fit: cover; flex: none; }
        .icon { display: flex; align-items: center; justify-content: center; font-size: 26px; background: var(--bg); }
        .info { flex: 1; min-width: 0; display: flex; flex-direction: column; }
        .name { overflow-wrap: anywhere; }
        .size { color: var(--muted); font-size: 13px; }
        .button { flex: none; display: inline-block; padding: 7px 16px; border-radius: 999px; background: var(--accent); color: #fff; text-decoration: none; font-size: 15px; border: none; }
        .pick { position: relative; display: block; text-align: center; padding: 14px; font-size: 17px; cursor: pointer; }
        .pick input { position: absolute; left: 0; top: 0; width: 1px; height: 1px; opacity: 0; }
        #progress { color: var(--muted); font-size: 14px; margin: 10px 0 0; min-height: 1.5em; }
        textarea { width: 100%; font: inherit; color: inherit; background: var(--bg); border: 1px solid var(--line); border-radius: 10px; padding: 10px; resize: vertical; }
        .hint { color: var(--muted); font-size: 13px; margin: 8px 0 0; }
        #done li { font-size: 15px; }
        .note { color: var(--muted); font-size: 13px; text-align: center; }
        </style>
        </head>
        <body>
        <main>
        <h1>\#(escape(String(localized: "传到手机")))</h1>
        <p class="from">\#(escape(String(localized: "来自「\(computerName)」上的 Pop")))</p>
        \#(shared)
        \#(downloads)
        <section>
        <h2>\#(escape(String(localized: "传到这台 Mac")))</h2>
        <label class="button pick">\#(escape(String(localized: "选择文件")))<input id="pick" type="file" multiple></label>
        <p id="progress"></p>
        <ul id="done"></ul>
        </section>
        <p class="note">\#(escape(String(localized: "文件会存进 Mac 的「下载」文件夹。Mac 上停止共享后，这个网页就打不开了。")))</p>
        </main>
        <script>
        const base = "\#(base)";
        const texts = \#(scriptTexts());
        const pick = document.getElementById("pick");
        const progress = document.getElementById("progress");
        const done = document.getElementById("done");
        function note(text) {
          const item = document.createElement("li");
          item.textContent = text;
          done.appendChild(item);
        }
        function send(file) {
          return new Promise(function (resolve) {
            const request = new XMLHttpRequest();
            request.open("PUT", base + "/u?name=" + encodeURIComponent(file.name));
            request.upload.onprogress = function (event) {
              if (event.lengthComputable) {
                progress.textContent = texts.sending.replace("{name}", file.name).replace("{percent}", Math.round(event.loaded / event.total * 100));
              }
            };
            request.onload = function () {
              note(request.status === 200 ? "✅ " + file.name : "❌ " + texts.failed.replace("{name}", file.name).replace("{reason}", request.responseText));
              resolve();
            };
            request.onerror = function () {
              note("❌ " + texts.disconnected.replace("{name}", file.name));
              resolve();
            };
            request.send(file);
          });
        }
        pick.addEventListener("change", async function () {
          const files = Array.from(pick.files);
          for (const file of files) {
            await send(file);
          }
          progress.textContent = files.length ? texts.finished : "";
          pick.value = "";
        });
        </script>
        </body>
        </html>
        """#
    }

    /// 网页脚本里用到的文字（JSON，{name} 这类占位符在脚本里替换）
    private static func scriptTexts() -> String {
        let texts = [
            "sending": String(localized: "正在传 {name}：{percent}%"),
            "failed": String(localized: "{name}（{reason}）"),
            "disconnected": String(localized: "{name}（连接断了）"),
            "finished": String(localized: "传完了，在 Mac 的「下载」文件夹里"),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: texts, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        // 放在 <script> 里：把 < 转义，文字里就不会出现 </script>
        return json.replacingOccurrences(of: "<", with: "\\u003c")
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func sizeLabel(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - 网页服务

/// 「传到手机」的网页服务：手机和 Mac 连同一个 Wi-Fi 时，手机扫码打开网页，下载 Mac 上选中的文件，
/// 或者把手机里的文件传到 Mac 的「下载」文件夹。网址里带一段随机口令，不知道网址的人打不开。
/// 所有状态都只在 queue 上读写。
final class LANShareServer: @unchecked Sendable {
    struct SharedFile: Equatable, Sendable {
        var url: URL
        /// 网页上显示、下载时用的名字
        var name: String
    }

    enum Event: Equatable, Sendable {
        /// 手机下载完了一个文件
        case downloaded(String)
        /// 手机传来一个文件，已经存好
        case received(URL)
    }

    enum Failure: LocalizedError {
        case stopped

        var errorDescription: String? { String(localized: "网页服务没能启动") }
    }

    let token: String
    private let queue = DispatchQueue(label: "io.github.whrss9527.pop.phone-share")
    private let uploadFolder: URL
    private let computerName: String
    private let onEvent: @Sendable (Event) -> Void
    private var files: [SharedFile]
    private var text: String?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var lastActivity = Date()

    /// 读一块、发一块，内存里最多放这么多
    static let chunkSize = 256 * 1024

    init(files: [SharedFile], text: String? = nil, uploadFolder: URL, computerName: String, token: String = LANShareServer.makeToken(),
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.files = files
        self.text = text
        self.uploadFolder = uploadFolder
        self.computerName = computerName
        self.token = token
        self.onEvent = onEvent
    }

    /// 10 位随机口令，去掉了容易看错的 0、o、1、l、i
    static func makeToken() -> String {
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<10).map { _ in alphabet.randomElement() ?? "a" })
    }

    /// 开始监听（系统挑一个空闲端口），返回端口号
    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if once.claim() {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case .failed(let error), .waiting(let error):
                    if once.claim() {
                        continuation.resume(throwing: error)
                    }
                    self?.stop()
                case .cancelled:
                    if once.claim() {
                        continuation.resume(throwing: Failure.stopped)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            queue.async {
                self.listener = listener
                listener.start(queue: self.queue)
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.stateUpdateHandler = nil
            self.listener?.newConnectionHandler = nil
            self.listener?.cancel()
            self.listener = nil
            for connection in self.connections.values {
                connection.cancel()
            }
            self.connections.removeAll()
        }
    }

    /// 换一批文件和文字（网址不变，手机刷新网页就能看到）
    func replaceContent(files: [SharedFile], text: String?) {
        queue.async {
            self.files = files
            self.text = text
            self.lastActivity = Date()
        }
    }

    /// 多久没有人访问了（传输中每发、收一块都算访问）
    func idleInterval(now: Date = Date()) -> TimeInterval {
        queue.sync { now.timeIntervalSince(lastActivity) }
    }

    // MARK: 连接

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed:
                connection.cancel()
                self?.connections[id] = nil
            case .cancelled:
                self?.connections[id] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveHead(connection, buffer: Data())
    }

    /// 读到空行（请求头结束）为止
    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(head: buffer.subdata(in: buffer.startIndex..<end.lowerBound),
                            body: buffer.subdata(in: end.upperBound..<buffer.endIndex), connection: connection)
            } else if isComplete || error != nil || buffer.count > 32 * 1024 {
                connection.cancel()
            } else {
                self.receiveHead(connection, buffer: buffer)
            }
        }
    }

    private func handle(head: Data, body: Data, connection: NWConnection) {
        lastActivity = Date()
        guard let request = HTTPRequestHead(head) else {
            return respond(connection, status: 400, text: String(localized: "请求格式不对"))
        }
        switch LANShareRoute.resolve(request, token: token, fileCount: files.count) {
        case .page:
            let items = files.enumerated().map { LANSharePage.item(index: $0.offset, url: $0.element.url, name: $0.element.name) }
            let html = LANSharePage.html(token: token, items: items, text: text, computerName: computerName)
            respond(connection, status: 200, type: "text/html; charset=utf-8", body: Data(html.utf8))
        case .file(let index, let inline):
            sendFile(files[index], inline: inline, connection: connection)
        case .upload(let name):
            guard let length = request.contentLength else {
                return respond(connection, status: 411, text: String(localized: "缺少文件大小"))
            }
            if request.headers["expect"]?.lowercased() == "100-continue" {
                connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
            }
            receiveUpload(name: name, length: length, initial: body, connection: connection)
        case .notFound:
            respond(connection, status: 404, text: String(localized: "没有这个网页"))
        }
    }

    // MARK: 回复

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 411: return "Length Required"
        case 507: return "Insufficient Storage"
        default: return "Internal Server Error"
        }
    }

    static func responseHead(status: Int, headers: [(String, String)]) -> Data {
        var text = "HTTP/1.1 \(status) \(reason(status))\r\n"
        for (name, value) in headers + [("Connection", "close")] {
            text += "\(name): \(value)\r\n"
        }
        return Data((text + "\r\n").utf8)
    }

    /// 下载时的文件名：老浏览器看 filename（只有 ASCII），新的看 filename*（UTF-8）
    static func contentDisposition(_ name: String, inline: Bool) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$&+-.^_`|~")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? "file"
        let fallback = String(name.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && scalar.value >= 0x20 && scalar != "\"" && scalar != "\\" ? Character(scalar) : "_"
        })
        return "\(inline ? "inline" : "attachment"); filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)"
    }

    static func mimeType(for name: String) -> String {
        UTType(filenameExtension: (name as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    private func respond(_ connection: NWConnection, status: Int, type: String = "text/plain; charset=utf-8", body: Data) {
        var data = Self.responseHead(status: status, headers: [("Content-Type", type), ("Content-Length", String(body.count)),
                                                               ("Cache-Control", "no-store")])
        data.append(body)
        connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func respond(_ connection: NWConnection, status: Int, text: String) {
        respond(connection, status: status, body: Data(text.utf8))
    }

    // MARK: 下载

    private func sendFile(_ file: SharedFile, inline: Bool, connection: NWConnection) {
        guard let handle = try? FileHandle(forReadingFrom: file.url) else {
            return respond(connection, status: 404, text: String(localized: "文件不见了"))
        }
        guard let size = try? handle.seekToEnd(), (try? handle.seek(toOffset: 0)) != nil else {
            try? handle.close()
            return respond(connection, status: 500, text: String(localized: "读不了这个文件"))
        }
        let head = Self.responseHead(status: 200, headers: [("Content-Type", Self.mimeType(for: file.name)),
                                                            ("Content-Length", String(size)),
                                                            ("Content-Disposition", Self.contentDisposition(file.name, inline: inline)),
                                                            ("Cache-Control", "no-store")])
        connection.send(content: head, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self.pump(handle, name: file.name, counts: !inline, connection: connection)
        })
    }

    /// 读一块发一块，前一块发出去了再读下一块
    private func pump(_ handle: FileHandle, name: String, counts: Bool, connection: NWConnection) {
        let chunk: Data
        do {
            chunk = try handle.read(upToCount: Self.chunkSize) ?? Data()
        } catch {
            try? handle.close()
            connection.cancel()
            return
        }
        lastActivity = Date()
        guard !chunk.isEmpty else {
            try? handle.close()
            if counts {
                onEvent(.downloaded(name))
            }
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self.pump(handle, name: name, counts: counts, connection: connection)
        })
    }

    // MARK: 上传

    /// 正在收的一个文件：先写进同一个磁盘上的临时文件夹，收完再挪到「下载」
    private final class Upload {
        let name: String
        let folder: URL
        let file: URL
        let handle: FileHandle
        var remaining: Int

        init(name: String, length: Int, near destination: URL) throws {
            self.name = name
            folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                 appropriateFor: destination, create: true)
            file = folder.appending(path: "upload")
            guard FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            handle = try FileHandle(forWritingTo: file)
            remaining = length
        }

        func append(_ data: Data) throws {
            let part = data.prefix(remaining)
            guard !part.isEmpty else { return }
            try handle.write(contentsOf: part)
            remaining -= part.count
        }

        func discard() {
            try? handle.close()
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// 手机传来的文件名：只留最后一段，去掉控制字符和开头的点（不存成隐藏文件）
    static func safeName(_ name: String) -> (base: String, ext: String?) {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
        var cleaned = String(scalars).replacingOccurrences(of: "\\", with: "/")
        cleaned = (cleaned.components(separatedBy: "/").last ?? "").replacingOccurrences(of: ":", with: "-")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        let ext = (cleaned as NSString).pathExtension
        var base = (cleaned as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        if base.count > 120 {
            base = String(base.prefix(120))
        }
        if base.isEmpty {
            base = String(localized: "来自手机")
        }
        return (base, ext.isEmpty || ext.count > 12 ? nil : ext)
    }

    private func receiveUpload(name: String, length: Int, initial: Data, connection: NWConnection) {
        let folder = uploadFolder
        let upload: Upload
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let free = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage, Int64(length) > free {
                return respond(connection, status: 507, text: String(localized: "Mac 上的空间不够"))
            }
            upload = try Upload(name: name, length: length, near: folder)
            try upload.append(initial)
        } catch {
            return respond(connection, status: 500, text: String(localized: "Mac 上存不了这个文件"))
        }
        receiveBody(upload, connection: connection)
    }

    private func receiveBody(_ upload: Upload, connection: NWConnection) {
        guard upload.remaining > 0 else {
            return finish(upload, connection: connection)
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                upload.discard()
                connection.cancel()
                return
            }
            if let data, !data.isEmpty {
                self.lastActivity = Date()
                do {
                    try upload.append(data)
                } catch {
                    upload.discard()
                    return self.respond(connection, status: 500, text: String(localized: "Mac 上写不进这个文件"))
                }
            }
            if upload.remaining == 0 {
                self.finish(upload, connection: connection)
            } else if isComplete || error != nil {
                upload.discard()
                connection.cancel()
            } else {
                self.receiveBody(upload, connection: connection)
            }
        }
    }

    private func finish(_ upload: Upload, connection: NWConnection) {
        try? upload.handle.close()
        let name = Self.safeName(upload.name)
        let destination = FileNames.available(in: uploadFolder, base: name.base, extension: name.ext)
        do {
            try FileManager.default.moveItem(at: upload.file, to: destination)
        } catch {
            upload.discard()
            return respond(connection, status: 500, text: String(localized: "Mac 上存不了这个文件"))
        }
        try? FileManager.default.removeItem(at: upload.folder)
        onEvent(.received(destination))
        respond(connection, status: 200, text: destination.lastPathComponent)
    }
}

/// 只让第一次调用生效（续体只能恢复一次）；只在一个串行队列上用
private final class Once: @unchecked Sendable {
    private var done = false

    func claim() -> Bool {
        defer { done = true }
        return !done
    }
}

// MARK: - 共享状态

/// 「传到手机」：同一时间只有一个网页服务。关掉卡片后继续共享，菜单栏里可以停止，一段时间没人访问自动停止。
@MainActor
final class PhoneShare: ObservableObject {
    static let shared = PhoneShare()

    /// 这么久没有人访问就自动停止
    static let idleLimit: TimeInterval = 10 * 60

    struct Failure: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? { message }
    }

    /// 手机打开的网址；没在共享时为 nil
    @Published private(set) var address: URL?
    private(set) var files: [URL] = []
    private(set) var text: String?
    private var server: LANShareServer?
    private var idleTimer: Timer?
    /// 共享选中的图片、文件夹时临时生成的文件
    private var scratch: URL?
    /// 手机下载了文件、传来了文件时提示（AppController 接上浮窗的提示）
    var onMessage: (String) -> Void = { _ in }

    var isSharing: Bool { server != nil }

    /// 手机传来的文件存在这里
    static var uploadFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
    }

    /// 开始共享这些文件和文字（可以都没有：只从手机传过来）。已经在共享时换成这些，网址不变
    func share(_ files: [URL], text: String? = nil, scratch: URL? = nil) async throws -> URL {
        let shared = files.map { LANShareServer.SharedFile(url: $0, name: $0.lastPathComponent) }
        if let server, let address {
            server.replaceContent(files: shared, text: text)
            replaceScratch(with: scratch)
            self.files = files
            self.text = text
            return address
        }
        guard let host = LANAddress.candidates().first else {
            throw Failure(message: String(localized: "这台 Mac 没有连上 Wi-Fi 或者网线，手机访问不到"))
        }
        let fresh = LANShareServer(files: shared, text: text, uploadFolder: Self.uploadFolder,
                                   computerName: LANAddress.computerName()) { [weak self] event in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
            }
        }
        let port: UInt16
        do {
            port = try await fresh.start()
        } catch {
            fresh.stop()
            throw Failure(message: String(localized: "网页服务没能启动：\(error.localizedDescription)"))
        }
        guard let url = URL(string: "http://\(host):\(port)/\(fresh.token)/") else {
            fresh.stop()
            throw Failure(message: String(localized: "网页服务没能启动"))
        }
        // 等待期间别的地方已经开始共享了：用先开的那个
        if let existing = self.server, let address {
            fresh.stop()
            existing.replaceContent(files: shared, text: text)
            replaceScratch(with: scratch)
            self.files = files
            self.text = text
            return address
        }
        self.server = fresh
        self.files = files
        self.text = text
        replaceScratch(with: scratch)
        address = url
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkIdle()
            }
        }
        return url
    }

    func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        server?.stop()
        server = nil
        address = nil
        files = []
        text = nil
        replaceScratch(with: nil)
    }

    /// 菜单栏里显示的状态；没在共享时为 nil
    func statusText() -> String? {
        guard isSharing else { return nil }
        if !files.isEmpty {
            return String(localized: "正在传到手机（\(files.count) 个文件）")
        }
        return text == nil ? String(localized: "正在接收手机传来的文件") : String(localized: "正在传到手机（一段文字）")
    }

    private func replaceScratch(with folder: URL?) {
        if let scratch, scratch != folder {
            try? FileManager.default.removeItem(at: scratch)
        }
        scratch = folder
    }

    private func checkIdle() {
        guard let server, server.idleInterval() > Self.idleLimit else { return }
        stop()
        onMessage(String(localized: "传到手机已停止（\(Int(Self.idleLimit / 60)) 分钟没人访问）"))
    }

    private func handle(_ event: LANShareServer.Event) {
        switch event {
        case .downloaded(let name):
            onMessage(String(localized: "手机下载了「\(name)」"))
        case .received(let url):
            onMessage(String(localized: "收到「\(url.lastPathComponent)」，在「下载」文件夹里"))
        }
    }

    /// 选中的内容换成能下载的文件：文件夹先打包成 zip，图片存成 PNG；选中的是文字就把文字放到网页上。
    /// 临时文件放在 scratch 里，停止共享时删掉
    static func prepare(_ content: ClassifiedContent) async throws -> (files: [URL], text: String?, scratch: URL?) {
        let fileManager = FileManager.default
        var scratch: URL?
        func scratchFolder() throws -> URL {
            if let scratch {
                return scratch
            }
            let folder = fileManager.temporaryDirectory.appending(path: "pop-phone-share-\(UUID().uuidString)")
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            scratch = folder
            return folder
        }
        var files: [URL] = []
        do {
            try await collect(content, into: &files, scratchFolder: scratchFolder)
        } catch {
            if let scratch {
                try? fileManager.removeItem(at: scratch)
            }
            throw error
        }
        var text: String?
        if case .text = content.selection, content.files.isEmpty, let selected = content.text, !selected.isEmpty {
            text = selected
        }
        return (files, text, scratch)
    }

    private static func collect(_ content: ClassifiedContent, into files: inout [URL], scratchFolder: () throws -> URL) async throws {
        let fileManager = FileManager.default
        if case .image(let data) = content.selection {
            let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
            guard let png else { throw Failure(message: String(localized: "读不了这张图片")) }
            let url = try scratchFolder().appending(path: ImageFiles.timestampedName(String(localized: "图片")) + ".png")
            try png.write(to: url)
            files.append(url)
        }
        for file in content.files {
            var isFolder: ObjCBool = false
            guard fileManager.fileExists(atPath: file.path(percentEncoded: false), isDirectory: &isFolder) else { continue }
            guard isFolder.boolValue else {
                files.append(file)
                continue
            }
            let folder = try scratchFolder()
            let zip = FileNames.available(in: folder, base: file.lastPathComponent, extension: "zip")
            let result = await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                                 arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                                             file.path(percentEncoded: false), zip.path(percentEncoded: false)],
                                                 stdin: nil, environment: [:], timeout: 600)
            guard case .success(let output) = result, output.status == 0 else {
                throw Failure(message: String(localized: "「\(file.lastPathComponent)」没能打包成 zip"))
            }
            files.append(zip)
        }
    }

    /// 结果卡片：二维码、网址、能下载的文件
    static func card(address: URL, files: [URL], text: String? = nil) -> ResultCard {
        let link = address.absoluteString
        var rows = [ResultCard.Row(label: String(localized: "网址"), value: link)]
        if !files.isEmpty {
            var names = files.prefix(4).map(\.lastPathComponent)
            if files.count > 4 {
                names.append(String(localized: "……一共 \(files.count) 个"))
            }
            rows.append(ResultCard.Row(label: String(localized: "可以下载"), value: names.joined(separator: "\n")))
        }
        if let text {
            rows.append(ResultCard.Row(label: String(localized: "文字"), value: text))
        }
        let body: String
        if !files.isEmpty {
            body = String(localized: "用手机相机扫码，在网页上点「下载」存到手机；也能从手机传文件过来")
        } else if text != nil {
            body = String(localized: "用手机相机扫码，网页上有这段文字，长按就能拷贝；也能从手机传文件过来")
        } else {
            body = String(localized: "用手机相机扫码，在网页上选文件传到这台 Mac 的「下载」文件夹")
        }
        return ResultCard(title: String(localized: "传到手机"), body: body,
                          detail: String(localized: "手机要和 Mac 连同一个 Wi-Fi。关掉卡片后继续共享，可以在菜单栏里停止；\(Int(idleLimit / 60)) 分钟没人访问自动停止"),
                          copyText: link, rows: rows, image: QRCode.generate(link),
                          buttons: [CardButton(title: String(localized: "停止共享"), action: .stopPhoneShare)])
    }
}
