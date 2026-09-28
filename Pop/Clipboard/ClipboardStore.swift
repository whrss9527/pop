import Foundation
import SQLite3

struct ClipboardItem: Identifiable, Equatable {
    enum Kind: String {
        case text
        case image
        case files
    }

    let id: Int64
    var kind: Kind
    /// 文字内容；文件是每行一个路径；图片为空
    var text: String
    /// 图片文件名（在 Images 文件夹里）
    var imageName: String?
    /// 复制时前台 App 的 Bundle ID
    var sourceApp: String?
    var createdAt: Date
    /// 最后一次复制或粘贴的时间，列表按它排序
    var usedAt: Date
    var pinned: Bool
    var byteSize: Int

    var fileURLs: [URL] {
        guard kind == .files else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }
}

/// 一次复制的内容，还没写进数据库。
struct ClipboardCapture: Equatable {
    var kind: ClipboardItem.Kind
    var text: String
    var imagePNG: Data?
    var sourceApp: String?

    /// 去重用：内容相同的复制只保留一条
    var hash: String {
        switch kind {
        case .text: return "text:" + Digests.sha256(Data(text.utf8))
        case .files: return "files:" + Digests.sha256(Data(text.utf8))
        case .image: return "image:" + Digests.sha256(imagePNG ?? Data())
        }
    }

    var byteSize: Int {
        kind == .image ? (imagePNG?.count ?? 0) : text.utf8.count
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 剪贴板历史数据库：~/Library/Application Support/Pop/Clipboard/history.sqlite（WAL 模式），
/// 图片单独存成 PNG 放在旁边的 Images 文件夹里。只存在本机，不会同步。
/// 所有操作都在一个串行队列里执行，可以从任意线程调用。
final class ClipboardStore: @unchecked Sendable {
    let directory: URL
    let imagesDirectory: URL
    private(set) var openError: String?

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "io.github.whrss9527.pop.clipboard")

    static var defaultDirectory: URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        return base.appending(path: "Pop/Clipboard", directoryHint: .isDirectory)
    }

    init(directory: URL = ClipboardStore.defaultDirectory) {
        self.directory = directory
        imagesDirectory = directory.appending(path: "Images", directoryHint: .isDirectory)
        queue.sync {
            openDatabase()
        }
    }

    deinit {
        if let db {
            sqlite3_close_v2(db)
        }
    }

    var isAvailable: Bool {
        queue.sync { db != nil }
    }

    // MARK: - 读写

    /// 记录一次复制。和已有记录内容相同时只更新时间（挪到最前面）。返回记录 ID。
    @discardableResult
    func add(_ capture: ClipboardCapture, at date: Date = Date()) -> Int64? {
        queue.sync { () -> Int64? in
            let hash = capture.hash
            var existing: Int64?
            _ = run("SELECT id FROM items WHERE hash = ?", [.text(hash)]) { statement in
                existing = sqlite3_column_int64(statement, 0)
            }
            if let existing {
                _ = run("UPDATE items SET used_at = ?, source_app = COALESCE(?, source_app) WHERE id = ?",
                        [.double(date.timeIntervalSince1970), .optionalText(capture.sourceApp), .int(existing)])
                return existing
            }
            var imageName: String?
            if capture.kind == .image {
                guard let png = capture.imagePNG else { return nil }
                let name = UUID().uuidString + ".png"
                do {
                    try png.write(to: imagesDirectory.appending(path: name), options: .atomic)
                } catch {
                    return nil
                }
                imageName = name
            }
            let inserted = run("""
                INSERT INTO items (kind, text, image_name, hash, source_app, created_at, used_at, pinned, byte_size)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
                """, [
                    .text(capture.kind.rawValue), .text(capture.text), .optionalText(imageName), .text(hash),
                    .optionalText(capture.sourceApp), .double(date.timeIntervalSince1970), .double(date.timeIntervalSince1970),
                    .int(Int64(capture.byteSize)),
                ])
            guard inserted, let db else { return nil }
            return sqlite3_last_insert_rowid(db)
        }
    }

    /// 固定的排在最前，其余按最近使用排序。search 不为空时按文字搜索（图片不参与搜索）。
    func items(matching search: String = "", limit: Int = 200) -> [ClipboardItem] {
        queue.sync { () -> [ClipboardItem] in
            var items: [ClipboardItem] = []
            let keyword = search.trimmingCharacters(in: .whitespacesAndNewlines)
            var values: [SQLValue] = []
            var sql = "SELECT \(Self.columns) FROM items"
            if !keyword.isEmpty {
                sql += " WHERE text LIKE ? ESCAPE '\\'"
                values.append(.text("%" + Self.escapeLike(keyword) + "%"))
            }
            sql += " ORDER BY pinned DESC, used_at DESC LIMIT ?"
            values.append(.int(Int64(max(limit, 0))))
            _ = run(sql, values) { statement in
                if let item = Self.item(from: statement) {
                    items.append(item)
                }
            }
            return items
        }
    }

    func item(id: Int64) -> ClipboardItem? {
        queue.sync { () -> ClipboardItem? in
            var result: ClipboardItem?
            _ = run("SELECT \(Self.columns) FROM items WHERE id = ?", [.int(id)]) { statement in
                result = Self.item(from: statement)
            }
            return result
        }
    }

    func setPinned(_ pinned: Bool, id: Int64) {
        queue.sync {
            _ = run("UPDATE items SET pinned = ? WHERE id = ?", [.int(pinned ? 1 : 0), .int(id)])
        }
    }

    func markUsed(id: Int64, at date: Date = Date()) {
        queue.sync {
            _ = run("UPDATE items SET used_at = ? WHERE id = ?", [.double(date.timeIntervalSince1970), .int(id)])
        }
    }

    func delete(id: Int64) {
        queue.sync {
            _ = removeRows(selecting: "SELECT id, image_name FROM items WHERE id = ?", [.int(id)])
        }
    }

    /// 清空历史；keepPinned 为 true 时保留固定的记录。
    func clear(keepPinned: Bool) {
        queue.sync {
            removeRows(selecting: keepPinned ? "SELECT id, image_name FROM items WHERE pinned = 0" : "SELECT id, image_name FROM items", [])
            execute("PRAGMA wal_checkpoint(TRUNCATE)")
            removeOrphanImages()
        }
    }

    /// 删除超过保存天数、或者超出条数上限的记录（固定的记录不受影响）。retentionDays 为 0 表示不按时间清理。
    @discardableResult
    func cleanup(retentionDays: Int, maxItems: Int, now: Date = Date()) -> Int {
        queue.sync { () -> Int in
            let cutoff = retentionDays > 0 ? now.timeIntervalSince1970 - Double(retentionDays) * 86_400 : -Double.greatestFiniteMagnitude
            let removed = removeRows(selecting: """
                SELECT id, image_name FROM items WHERE pinned = 0 AND (used_at < ? OR id NOT IN (
                    SELECT id FROM items WHERE pinned = 0 ORDER BY used_at DESC LIMIT ?
                ))
                """, [.double(cutoff), .int(Int64(max(maxItems, 0)))])
            removeOrphanImages()
            return removed
        }
    }

    func statistics() -> (count: Int, bytes: Int) {
        queue.sync { () -> (count: Int, bytes: Int) in
            var result = (count: 0, bytes: 0)
            _ = run("SELECT COUNT(*), COALESCE(SUM(byte_size), 0) FROM items", []) { statement in
                result = (count: Int(sqlite3_column_int64(statement, 0)), bytes: Int(sqlite3_column_int64(statement, 1)))
            }
            return result
        }
    }

    func imageURL(for item: ClipboardItem) -> URL? {
        item.imageName.map { imagesDirectory.appending(path: $0) }
    }

    // MARK: - SQLite

    private enum SQLValue {
        case text(String)
        case int(Int64)
        case double(Double)
        case null

        static func optionalText(_ value: String?) -> SQLValue {
            value.map(SQLValue.text) ?? .null
        }
    }

    private static let columns = "id, kind, text, image_name, source_app, created_at, used_at, pinned, byte_size"

    private func openDatabase() {
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            openError = "无法创建文件夹：\(error.localizedDescription)"
            return
        }
        let path = directory.appending(path: "history.sqlite").path(percentEncoded: false)
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &opened, flags, nil) == SQLITE_OK, let handle = opened else {
            openError = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            sqlite3_close_v2(opened)
            return
        }
        db = handle
        execute("PRAGMA journal_mode = WAL")
        execute("PRAGMA synchronous = NORMAL")
        execute("""
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL,
                text TEXT NOT NULL DEFAULT '',
                image_name TEXT,
                hash TEXT NOT NULL UNIQUE,
                source_app TEXT,
                created_at REAL NOT NULL,
                used_at REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                byte_size INTEGER NOT NULL DEFAULT 0
            )
            """)
        execute("CREATE INDEX IF NOT EXISTS items_order ON items (pinned DESC, used_at DESC)")
        execute("PRAGMA user_version = 1")
    }

    private func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// 执行一条语句，逐行回调结果。只能在 queue 里调用。
    private func run(_ sql: String, _ values: [SQLValue], row: ((OpaquePointer) -> Void)? = nil) -> Bool {
        guard let db else { return false }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else { return false }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .text(let text):
                sqlite3_bind_text(statement, position, text, -1, sqliteTransient)
            case .int(let number):
                sqlite3_bind_int64(statement, position, number)
            case .double(let number):
                sqlite3_bind_double(statement, position, number)
            case .null:
                sqlite3_bind_null(statement, position)
            }
        }
        while true {
            let status = sqlite3_step(statement)
            guard status == SQLITE_ROW else { return status == SQLITE_DONE }
            row?(statement)
        }
    }

    /// 删除查询出来的记录和对应的图片文件，返回删除条数。只能在 queue 里调用。
    @discardableResult
    private func removeRows(selecting sql: String, _ values: [SQLValue]) -> Int {
        var victims: [(id: Int64, imageName: String?)] = []
        _ = run(sql, values) { statement in
            victims.append((id: sqlite3_column_int64(statement, 0), imageName: Self.text(statement, 1)))
        }
        guard !victims.isEmpty else { return 0 }
        execute("BEGIN")
        for victim in victims {
            _ = run("DELETE FROM items WHERE id = ?", [.int(victim.id)])
        }
        execute("COMMIT")
        for victim in victims {
            if let name = victim.imageName {
                try? FileManager.default.removeItem(at: imagesDirectory.appending(path: name))
            }
        }
        return victims.count
    }

    /// 删掉数据库里没有引用的图片（比如写完图片还没来得及记录就退出了）。只能在 queue 里调用。
    private func removeOrphanImages() {
        var referenced = Set<String>()
        _ = run("SELECT image_name FROM items WHERE image_name IS NOT NULL", []) { statement in
            if let name = Self.text(statement, 0) {
                referenced.insert(name)
            }
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path(percentEncoded: false))) ?? []
        for name in files where name.hasSuffix(".png") && !referenced.contains(name) {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: name))
        }
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        let length = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: pointer, count: length), as: UTF8.self)
    }

    private static func item(from statement: OpaquePointer) -> ClipboardItem? {
        guard let kind = text(statement, 1).flatMap(ClipboardItem.Kind.init(rawValue:)) else { return nil }
        return ClipboardItem(id: sqlite3_column_int64(statement, 0),
                             kind: kind,
                             text: text(statement, 2) ?? "",
                             imageName: text(statement, 3),
                             sourceApp: text(statement, 4),
                             createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                             usedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                             pinned: sqlite3_column_int(statement, 7) != 0,
                             byteSize: Int(sqlite3_column_int64(statement, 8)))
    }

    static func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}
