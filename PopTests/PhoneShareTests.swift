import XCTest
@testable import Pop

/// 收集网页服务发出的事件（在服务自己的队列上调用）
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [LANShareServer.Event] = []

    func append(_ event: LANShareServer.Event) {
        lock.lock()
        items.append(event)
        lock.unlock()
    }

    var all: [LANShareServer.Event] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

/// 用最原始的 TCP 连接发一个 HTTP 请求，读到对方关掉连接为止
private struct RawResponse {
    var status: Int
    var head: String
    var body: Data

    static func fetch(port: UInt16, _ request: Data) throws -> RawResponse {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(socket) }
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { throw POSIXError(.ECONNREFUSED) }
        try request.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Void in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let count = Darwin.send(socket, base + sent, buffer.count - sent, 0)
                guard count > 0 else { throw POSIXError(.EPIPE) }
                sent += count
            }
        }
        var response = Data()
        let capacity = 64 * 1024
        var chunk = [UInt8](repeating: 0, count: capacity)
        while true {
            let count = Darwin.recv(socket, &chunk, capacity, 0)
            guard count > 0 else { break }
            response.append(contentsOf: chunk[0..<count])
        }
        guard let end = response.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: response.subdata(in: response.startIndex..<end.lowerBound), encoding: .utf8),
              let status = head.split(separator: " ").dropFirst().first.flatMap({ Int($0) }) else {
            throw POSIXError(.EBADMSG)
        }
        return RawResponse(status: status, head: head, body: response.subdata(in: end.upperBound..<response.endIndex))
    }

    static func get(port: UInt16, _ path: String) throws -> RawResponse {
        try fetch(port: port, Data("GET \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8))
    }

    static func put(port: UInt16, _ path: String, body: Data) throws -> RawResponse {
        var request = Data("PUT \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
        request.append(body)
        return try fetch(port: port, request)
    }
}

final class PhoneShareTests: XCTestCase {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pop-phone-share-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testParsesRequestHead() throws {
        let head = "GET /k7m2p9qx4t/f/1?view=1 HTTP/1.1\r\nHost: 192.168.1.23:52731\r\nContent-Length: 12\r\nExpect: 100-continue"
        let request = try XCTUnwrap(HTTPRequestHead(Data(head.utf8)))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/k7m2p9qx4t/f/1")
        XCTAssertEqual(request.query, ["view": "1"])
        XCTAssertEqual(request.headers["host"], "192.168.1.23:52731")
        XCTAssertEqual(request.headers["expect"], "100-continue")
        XCTAssertEqual(request.contentLength, 12)
        XCTAssertNil(HTTPRequestHead(Data("hello".utf8)))
        XCTAssertNil(HTTPRequestHead(Data("GET / SMTP\r\n".utf8)))
        let upload = try XCTUnwrap(HTTPRequestHead(Data("PUT /t/u?name=%E7%85%A7%E7%89%87.jpg HTTP/1.1".utf8)))
        XCTAssertEqual(upload.query["name"], "照片.jpg")
        XCTAssertNil(upload.contentLength)
    }

    func testRoutesNeedTheToken() throws {
        func route(_ line: String, files: Int = 2) -> LANShareRoute {
            guard let request = HTTPRequestHead(Data((line + " HTTP/1.1").utf8)) else { return .notFound }
            return LANShareRoute.resolve(request, token: "k7m2p9qx4t", fileCount: files)
        }
        XCTAssertEqual(route("GET /k7m2p9qx4t/"), .page)
        XCTAssertEqual(route("GET /k7m2p9qx4t"), .page)
        XCTAssertEqual(route("GET /k7m2p9qx4t/f/1"), .file(index: 1, inline: false))
        XCTAssertEqual(route("GET /k7m2p9qx4t/f/0?view=1"), .file(index: 0, inline: true))
        XCTAssertEqual(route("GET /k7m2p9qx4t/f/2"), .notFound)
        XCTAssertEqual(route("GET /k7m2p9qx4t/f/-1"), .notFound)
        XCTAssertEqual(route("PUT /k7m2p9qx4t/u?name=a.txt"), .upload(name: "a.txt"))
        XCTAssertEqual(route("POST /k7m2p9qx4t/u?name=a.txt"), .upload(name: "a.txt"))
        XCTAssertEqual(route("GET /k7m2p9qx4t/u"), .notFound)
        XCTAssertEqual(route("DELETE /k7m2p9qx4t/f/0"), .notFound)
        XCTAssertEqual(route("GET /"), .notFound)
        XCTAssertEqual(route("GET /wrongtoken/f/0"), .notFound)
        XCTAssertEqual(route("GET /favicon.ico"), .notFound)
        XCTAssertEqual(LANShareServer.makeToken().count, 10)
        XCTAssertNotEqual(LANShareServer.makeToken(), LANShareServer.makeToken())
    }

    func testPageListsFilesAndText() {
        let items = [LANSharePage.Item(index: 0, name: "<季度>报告.pdf", size: 2_400_000, preview: false),
                     LANSharePage.Item(index: 1, name: "照片.jpg", size: 1_200_000, preview: true)]
        let html = LANSharePage.html(token: "k7m2p9qx4t", items: items, text: "https://example.com/a?b=1&c=2", computerName: "小王的 Mac")
        XCTAssertTrue(html.contains("&lt;季度&gt;报告.pdf"))
        XCTAssertFalse(html.contains("<季度>"))
        XCTAssertTrue(html.contains("href=\"/k7m2p9qx4t/f/0\" download"))
        XCTAssertTrue(html.contains("<a href=\"/k7m2p9qx4t/f/1?view=1\"><img src=\"/k7m2p9qx4t/f/1?view=1\""))
        XCTAssertTrue(html.contains("长按存到相册"))
        XCTAssertFalse(html.contains("src=\"/k7m2p9qx4t/f/0?view=1\""))
        XCTAssertTrue(html.contains("来自「小王的 Mac」"))
        XCTAssertTrue(html.contains("const base = \"/k7m2p9qx4t\";"))
        XCTAssertTrue(html.contains("<textarea readonly"))
        XCTAssertTrue(html.contains("https://example.com/a?b=1&amp;c=2</textarea>"))
        XCTAssertTrue(html.contains(">打开链接</a>"))

        let empty = LANSharePage.html(token: "k7m2p9qx4t", items: [], computerName: "Mac")
        XCTAssertFalse(empty.contains("存到手机"))
        XCTAssertFalse(empty.contains("<textarea"))
        XCTAssertFalse(empty.contains("长按存到相册"))
        XCTAssertTrue(empty.contains("传到这台 Mac"))
        // 普通文字没有「打开链接」
        XCTAssertFalse(LANSharePage.html(token: "t", items: [], text: "周一例会", computerName: "Mac").contains("打开链接"))
    }

    func testHeadersForDownloads() {
        XCTAssertEqual(LANShareServer.contentDisposition("季度报告 v2.pdf", inline: false),
                       "attachment; filename=\"____ v2.pdf\"; filename*=UTF-8''%E5%AD%A3%E5%BA%A6%E6%8A%A5%E5%91%8A%20v2.pdf")
        XCTAssertTrue(LANShareServer.contentDisposition("a\"b.png", inline: true).hasPrefix("inline; filename=\"a_b.png\""))
        XCTAssertEqual(LANShareServer.mimeType(for: "报告.pdf"), "application/pdf")
        XCTAssertEqual(LANShareServer.mimeType(for: "照片.jpg"), "image/jpeg")
        XCTAssertEqual(LANShareServer.mimeType(for: "没有扩展名"), "application/octet-stream")
        let head = String(decoding: LANShareServer.responseHead(status: 404, headers: [("Content-Length", "0")]), as: UTF8.self)
        XCTAssertEqual(head, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    }

    func testUploadNamesStayInTheFolder() {
        XCTAssertTrue(LANShareServer.safeName("../../etc/passwd") == ("passwd", nil))
        XCTAssertTrue(LANShareServer.safeName(".hidden.txt") == ("hidden", "txt"))
        XCTAssertTrue(LANShareServer.safeName("a:b.jpg") == ("a-b", "jpg"))
        XCTAssertTrue(LANShareServer.safeName(#"C:\Users\照片.png"#) == ("照片", "png"))
        XCTAssertTrue(LANShareServer.safeName("IMG_0001.HEIC") == ("IMG_0001", "HEIC"))
        XCTAssertTrue(LANShareServer.safeName("") == ("来自手机", nil))
        XCTAssertTrue(LANShareServer.safeName("  \n ") == ("来自手机", nil))
    }

    func testPicksAddressesPhonesCanReach() {
        let interfaces = [LANAddress.Interface(name: "utun3", address: "10.8.0.2"),
                          LANAddress.Interface(name: "bridge100", address: "192.168.2.1"),
                          LANAddress.Interface(name: "en5", address: "10.0.0.9"),
                          LANAddress.Interface(name: "en0", address: "192.168.1.23"),
                          LANAddress.Interface(name: "en7", address: "169.254.12.3"),
                          LANAddress.Interface(name: "vmnet8", address: "172.16.1.1"),
                          LANAddress.Interface(name: "en1", address: "8.8.8.8")]
        XCTAssertEqual(LANAddress.candidates(interfaces), ["192.168.1.23", "10.0.0.9", "192.168.2.1", "8.8.8.8"])
        XCTAssertTrue(LANAddress.isPrivate("172.20.1.1"))
        XCTAssertFalse(LANAddress.isPrivate("172.32.1.1"))
        XCTAssertFalse(LANAddress.isPrivate("fe80::1"))
        XCTAssertFalse(LANAddress.computerName().isEmpty)
    }

    func testServesFilesAndReceivesUploads() async throws {
        let base = try folder()
        let shared = base.appending(path: "报告.txt")
        try Data("你好，手机".utf8).write(to: shared)
        let uploads = base.appending(path: "下载")
        let log = EventLog()
        let server = LANShareServer(files: [LANShareServer.SharedFile(url: shared, name: "报告.txt")], text: "https://example.com",
                                    uploadFolder: uploads, computerName: "测试机", token: "testtoken23") { event in
            log.append(event)
        }
        let port = try await server.start()
        defer { server.stop() }
        XCTAssertGreaterThan(port, 0)

        let page = try RawResponse.get(port: port, "/testtoken23/")
        XCTAssertEqual(page.status, 200)
        XCTAssertTrue(page.head.contains("Content-Type: text/html; charset=utf-8"), page.head)
        let html = String(decoding: page.body, as: UTF8.self)
        XCTAssertTrue(html.contains("报告.txt"))
        XCTAssertTrue(html.contains("来自「测试机」"))
        XCTAssertTrue(html.contains("https://example.com</textarea>"))

        let file = try RawResponse.get(port: port, "/testtoken23/f/0")
        XCTAssertEqual(file.status, 200)
        XCTAssertEqual(file.body, Data("你好，手机".utf8))
        XCTAssertTrue(file.head.contains("Content-Disposition: attachment;"), file.head)
        XCTAssertTrue(file.head.contains("Content-Length: \(Data("你好，手机".utf8).count)"), file.head)
        XCTAssertEqual(log.all, [.downloaded("报告.txt")])
        // 网页里的缩略图不算下载
        XCTAssertEqual(try RawResponse.get(port: port, "/testtoken23/f/0?view=1").status, 200)
        XCTAssertEqual(log.all.count, 1)

        XCTAssertEqual(try RawResponse.get(port: port, "/wrongtoken/").status, 404)
        XCTAssertEqual(try RawResponse.get(port: port, "/testtoken23/f/5").status, 404)

        // 比一次读到的多：要分好几次收
        var photo = Data(count: 700_000)
        for index in photo.indices {
            photo[index] = UInt8(truncatingIfNeeded: index &* 31)
        }
        let first = try RawResponse.put(port: port, "/testtoken23/u?name=%E7%85%A7%E7%89%87.jpg", body: photo)
        XCTAssertEqual(first.status, 200)
        XCTAssertEqual(String(decoding: first.body, as: UTF8.self), "照片.jpg")
        XCTAssertEqual(try Data(contentsOf: uploads.appending(path: "照片.jpg")), photo)
        let second = try RawResponse.put(port: port, "/testtoken23/u?name=%E7%85%A7%E7%89%87.jpg", body: Data("第二张".utf8))
        XCTAssertEqual(String(decoding: second.body, as: UTF8.self), "照片 2.jpg")
        XCTAssertEqual(log.all.count, 3)
        XCTAssertEqual(log.all.last, .received(uploads.appending(path: "照片 2.jpg")))
        // 只收到这两个文件，临时文件都挪走了
        let names = try FileManager.default.contentsOfDirectory(atPath: uploads.path(percentEncoded: false)).sorted()
        XCTAssertEqual(names, ["照片 2.jpg", "照片.jpg"])
        XCTAssertLessThan(server.idleInterval(), 60)
    }

    @MainActor
    func testPreparesFoldersImagesAndText() async throws {
        let base = try folder()
        let album = base.appending(path: "相册")
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: album.appending(path: "1.txt"))
        let note = base.appending(path: "说明.txt")
        try Data("b".utf8).write(to: note)

        let prepared = try await PhoneShare.prepare(ContentClassifier.classify(.files([album, note])))
        XCTAssertEqual(prepared.files.map(\.lastPathComponent), ["相册.zip", "说明.txt"])
        XCTAssertNil(prepared.text)
        let scratch = try XCTUnwrap(prepared.scratch)
        addTeardownBlock { try? FileManager.default.removeItem(at: scratch) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.files[0].path(percentEncoded: false)))
        XCTAssertEqual(prepared.files[0].deletingLastPathComponent().standardizedFileURL, scratch.standardizedFileURL)

        let text = try await PhoneShare.prepare(ContentClassifier.classify(.text("周一例会")))
        XCTAssertEqual(text.text, "周一例会")
        XCTAssertTrue(text.files.isEmpty)
        XCTAssertNil(text.scratch)

        let nothing = try await PhoneShare.prepare(.empty)
        XCTAssertTrue(nothing.files.isEmpty)
        XCTAssertNil(nothing.text)

        let card = PhoneShare.card(address: try XCTUnwrap(URL(string: "http://192.168.1.23:52731/k7m2p9qx4t/")), files: prepared.files)
        XCTAssertEqual(card.copyText, "http://192.168.1.23:52731/k7m2p9qx4t/")
        XCTAssertNotNil(card.image)
        XCTAssertEqual(card.rows.map(\.label), ["网址", "可以下载"])
        XCTAssertEqual(card.buttons, [CardButton(title: "停止共享", action: .stopPhoneShare)])
        XCTAssertTrue(SendToPhonePlugin().info.canHandle(.empty))
    }
}
