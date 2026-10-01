import AppKit
import PDFKit
import WebKit

/// 网页存档：在后台打开一个网页，整页存成一页长 PDF（文字能选、能搜，链接能点）、一张长图，
/// 或者只取出正文存成 Markdown（做笔记用）。
/// 用的是 Pop 自己的网页视图，没有浏览器里的登录状态：要登录才能看的页面存下来是登录页。
enum WebCapture {
    enum Format: String, Equatable, CaseIterable {
        case pdf
        case image
        case markdown

        var title: String {
            switch self {
            case .pdf: return String(localized: "存成 PDF")
            case .image: return String(localized: "存成长图")
            case .markdown: return String(localized: "存成 Markdown")
            }
        }
    }

    struct Failure: LocalizedError, Equatable {
        let message: String

        var errorDescription: String? { message }
    }

    /// 选中网址时的卡片：三种存法各一个按钮
    static func card(_ url: URL) -> ResultCard {
        ResultCard(title: String(localized: "网页存档"), body: url.absoluteString,
                   detail: String(localized: "在后台打开网页存到「下载」：PDF 和长图是整页，Markdown 只取正文；要登录的页面存下来是登录页"),
                   buttons: Format.allCases.map { CardButton(title: $0.title, action: .captureWeb(url, $0)) })
    }

    /// 存下来的网页：一页 PDF 和网页标题
    struct Page {
        let pdf: Data
        let title: String?
    }

    /// 网页的正文部分（HTML，链接和图片已经是完整的网址）和标题
    struct Article {
        let html: String
        let title: String?
    }

    /// 网页排版的宽度（点）
    static let pageWidth: CGFloat = 1200
    /// 长图最长这么多像素、一共最多这么多像素，再大就等比缩小
    static let maxImageHeight: CGFloat = 32_000
    static let maxImagePixels: CGFloat = 24_000_000

    /// 打开 url（或者直接给一段 HTML，测试用），整页存成一页 PDF
    @MainActor
    static func load(_ url: URL?, html: String? = nil, timeout: TimeInterval = 40) async throws -> Page {
        let loader = PageLoader(width: pageWidth)
        defer { loader.close() }
        try await loader.load(url: url, html: html, timeout: timeout)
        await loader.settle()
        return Page(pdf: try await loader.pdf(), title: loader.title)
    }

    /// 打开 url（或者直接给一段 HTML，测试用），取出正文部分
    @MainActor
    static func loadArticle(_ url: URL?, html: String? = nil, timeout: TimeInterval = 40) async throws -> Article {
        let loader = PageLoader(width: pageWidth)
        defer { loader.close() }
        try await loader.load(url: url, html: html, timeout: timeout)
        await loader.settleForText()
        guard let content = await loader.mainContent(), !content.isEmpty else {
            throw Failure(message: String(localized: "网页里没有找到正文"))
        }
        return Article(html: content, title: loader.title)
    }

    /// 正文转成 Markdown，最前面是标题和原文链接；正文自己以一级标题开头时，原文链接放在那个标题下面
    static func markdown(title: String?, url: URL, html: String) -> String? {
        guard let body = HTMLToMarkdown.convert(html)?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
            return nil
        }
        let address = url.absoluteString
        let source = String(localized: "原文：<\(address)>")
        if body.hasPrefix("# ") {
            var lines = body.components(separatedBy: "\n")
            lines.insert(contentsOf: ["", source], at: 1)
            return lines.joined(separator: "\n") + "\n"
        }
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = trimmed.isEmpty ? (url.host() ?? address) : trimmed
        return "# \(heading)\n\n\(source)\n\n\(body)\n"
    }

    /// 一页 PDF 画成 PNG：按 1.5 倍画，太长、太大时整体缩小。比较慢，在后台调用
    static func image(fromPDF data: Data) throws -> Data {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else {
            throw Failure(message: String(localized: "网页没能画出来"))
        }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw Failure(message: String(localized: "网页是空的")) }
        let scale = min(1.5, maxImageHeight / bounds.height, (maxImagePixels / (bounds.width * bounds.height)).squareRoot())
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(message: String(localized: "网页太大了，画不出来"))
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        if let pageRef = page.pageRef {
            context.drawPDFPage(pageRef)
        }
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Failure(message: String(localized: "网页没能画出来"))
        }
        return png
    }

    /// 文件名用网页标题；没有标题时用网址的主机名
    static func fileName(title: String?, url: URL) -> String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? (url.host() ?? String(localized: "网页")) : trimmed
        let safe = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return String(safe.prefix(80))
    }

    /// 打开网页、存到「下载」，返回文件位置
    @MainActor
    static func capture(_ url: URL, format: Format) async throws -> URL {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if format == .markdown {
            let article = try await loadArticle(url)
            let html = article.html
            let title = article.title
            guard let text = await runInBackground({ WebCapture.markdown(title: title, url: url, html: html) }) else {
                throw Failure(message: String(localized: "网页里没有找到正文"))
            }
            let output = FileNames.available(in: folder, base: fileName(title: article.title, url: url), extension: "md")
            try Data(text.utf8).write(to: output)
            return output
        }
        let page = try await load(url)
        let name = fileName(title: page.title, url: url)
        let output: URL
        if format == .image {
            let data = page.pdf
            let png = try await runInBackground { Result { try WebCapture.image(fromPDF: data) } }.get()
            output = FileNames.available(in: folder, base: name, extension: "png")
            try png.write(to: output)
        } else {
            output = FileNames.available(in: folder, base: name, extension: "pdf")
            try page.pdf.write(to: output)
        }
        return output
    }
}

/// 在后台打开网页的视图。加载完以后往下滚一遍、让懒加载的图片都加载出来，再回到顶上
@MainActor
private final class PageLoader: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var continuation: CheckedContinuation<Void, Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    /// 网页已经开始显示内容
    private var committed = false
    private(set) var title: String?

    init(width: CGFloat) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // 按 Safari 的写法报浏览器名字，有的网站不认别的
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 900), configuration: configuration)
        // 存档按浅色的样子存，不跟着系统的深色外观走
        webView.appearance = NSAppearance(named: .aqua)
        super.init()
        webView.navigationDelegate = self
    }

    /// 打开网页，等它加载完。有的网页里个别资源（比如字体）一直加载不完：内容出来以后最多再等 12 秒
    func load(url: URL?, html: String?, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            if let html {
                webView.loadHTMLString(html, baseURL: url)
            } else if let url {
                webView.load(URLRequest(url: url, timeoutInterval: timeout))
            } else {
                finish(.failure(WebCapture.Failure(message: String(localized: "没有网址"))))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.finish(self.committed ? .success(()) : .failure(WebCapture.Failure(message: String(localized: "网页打开太慢，已经放弃"))))
                }
            }
        }
        // 网页视图的 title 有时比加载完晚一步才更新，直接问网页
        let documentTitle = try? await webView.evaluateJavaScript("document.title") as? String
        title = [documentTitle, webView.title].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// 存正文时只要往下滚一遍，让滚动时才加载的内容出来，不用等图片
    func settleForText() async {
        await scrollThrough()
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0); true")
    }

    /// 取出正文部分的 HTML
    func mainContent() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            webView.callAsyncJavaScript(Self.mainContentScript, arguments: [:], in: nil, in: .defaultClient) { result in
                continuation.resume(returning: (try? result.get()) as? String)
            }
        }
    }

    /// 找正文：只有一篇（或者最长的一篇比第二长的长很多）的 article，其次是 main，都没有就用整个 body。
    /// 复制一份再去掉看不见的元素、导航、侧栏、页脚、表单、脚本，链接和图片换成完整的网址
    private static let mainContentScript = """
    const length = (element) => (element.innerText || "").trim().length;
    const outermost = (list) => list.filter((element) => !list.some((other) => other !== element && other.contains(element)));
    const pick = (selector) => {
        const found = outermost(Array.from(document.querySelectorAll(selector))).map((element) => [element, length(element)]).sort((a, b) => b[1] - a[1]);
        if (found.length === 0 || found[0][1] < 200) { return null; }
        if (found.length > 1 && found[0][1] < found[1][1] * 3) { return null; }
        return found[0][0];
    };
    const root = pick('article, [itemprop="articleBody"]') || pick('main, [role="main"]') || document.body;
    if (!root) { return ""; }
    const hidden = [];
    for (const element of root.querySelectorAll("*")) {
        const style = getComputedStyle(element);
        if (style.display === "none" || style.visibility === "hidden") { element.setAttribute("data-pop-hidden", ""); hidden.push(element); }
    }
    const copy = root.cloneNode(true);
    for (const element of hidden) { element.removeAttribute("data-pop-hidden"); }
    copy.querySelectorAll('[data-pop-hidden], script, style, noscript, template, iframe, nav, aside, form, button, dialog, footer, video, audio, source, [role="navigation"], [role="complementary"], [role="banner"], [role="contentinfo"], [aria-hidden="true"]').forEach((element) => element.remove());
    if (root === document.body) {
        copy.querySelectorAll("header").forEach((element) => { if (!element.closest('article, main, [role="main"]')) { element.remove(); } });
    }
    const absolute = (value) => { try { return new URL(value, document.baseURI).href; } catch (error) { return ""; } };
    copy.querySelectorAll("a[href]").forEach((link) => {
        const raw = link.getAttribute("href") || "";
        // 页内跳转（标题旁边的 # 链接）留着，转 Markdown 时只留文字
        if (raw.startsWith("#")) { return; }
        const href = absolute(raw);
        if (/^(https?|mailto):/i.test(href)) { link.setAttribute("href", href); } else { link.removeAttribute("href"); }
    });
    copy.querySelectorAll("img").forEach((image) => {
        const fromSet = (image.getAttribute("srcset") || "").split(",")[0].trim().split(/\\s+/)[0];
        const raw = image.getAttribute("data-src") || image.getAttribute("data-original") || image.getAttribute("data-lazy-src") || image.getAttribute("src") || fromSet || "";
        const source = raw.startsWith("data:") ? "" : absolute(raw);
        if (!/^https?:/i.test(source)) { image.remove(); return; }
        image.setAttribute("src", source);
        image.removeAttribute("srcset");
    });
    return copy.outerHTML;
    """

    /// 往下滚到底、让懒加载的图片都加载出来，再回到顶上
    func settle() async {
        await scrollThrough()
        await loadImages(seconds: 10)
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0); true")
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    /// 一屏一屏往下滚到底（最多 30 屏），每屏停一下
    private func scrollThrough() async {
        for _ in 0..<30 {
            let result = try? await webView.evaluateJavaScript("""
            window.scrollBy(0, window.innerHeight);
            (window.innerHeight + window.scrollY) >= document.documentElement.scrollHeight - 2
            """)
            try? await Task.sleep(nanoseconds: 150_000_000)
            if (result as? Bool) == true {
                break
            }
        }
    }

    /// 懒加载的图片改成立刻加载（包括地址写在 data-src 里的），等它们加载完，最多等 seconds 秒
    private func loadImages(seconds: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiting = continuation
            webView.callAsyncJavaScript(Self.loadImagesScript, arguments: [:], in: nil, in: .defaultClient) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopWaiting() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                MainActor.assumeIsolated { self?.stopWaiting() }
            }
        }
    }

    private static let loadImagesScript = """
    const images = Array.from(document.images);
    for (const image of images) {
        if (image.loading === "lazy") { image.loading = "eager"; }
        const lazy = image.dataset.src || image.dataset.original || image.dataset.lazySrc;
        const current = image.getAttribute("src") || "";
        if (lazy && (current === "" || current.startsWith("data:"))) { image.src = lazy; }
    }
    await Promise.all(images.filter(image => !image.complete).map(image => new Promise(done => {
        image.addEventListener("load", done, { once: true });
        image.addEventListener("error", done, { once: true });
    })));
    return images.length;
    """

    func pdf() async throws -> Data {
        do {
            return try await webView.pdf(configuration: WKPDFConfiguration())
        } catch {
            throw WebCapture.Failure(message: String(localized: "网页没能存下来：\(error.localizedDescription)"))
        }
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    private func stopWaiting() {
        guard let waiting else { return }
        self.waiting = nil
        waiting.resume()
    }

    /// 被新的跳转取代的那次加载不算失败
    private func fail(_ error: Error) {
        let error = error as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            return
        }
        finish(.failure(WebCapture.Failure(message: String(localized: "网页打不开：\(error.localizedDescription)"))))
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            committed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                MainActor.assumeIsolated { self?.finish(.success(())) }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            finish(.success(()))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            fail(error)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            fail(error)
        }
    }
}
