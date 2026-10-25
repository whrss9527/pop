import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// 只读一个普通文件的开头，输出固定宽度的十六进制与 ASCII，不解释或执行文件内容。
enum BytePreview {
    static let byteLimit = 4096
    static let lineWidth = 16

    enum Failure: Error, Equatable {
        case requiresSingleFile
        case notLocalFile
        case notRegularFile
        case cannotRead
    }

    struct Snapshot: Equatable {
        let name: String
        let data: Data
        /// 打开文件时观察到的大小；文件可能在读取后继续变化。
        let observedFileSize: Int64

        var truncated: Bool { observedFileSize > Int64(data.count) }
        var text: String { BytePreview.format(data) }
    }

    static func read(_ files: [URL]) throws -> Snapshot {
        guard files.count == 1 else { throw Failure.requiresSingleFile }
        // Foundation 在不同系统上可能无法把非法 URL 值还原成可用的元素。
        guard let file = files.first else { throw Failure.notLocalFile }
        // 先检查尚未转成文件系统路径的编码形式，避免 NUL 在 Darwin 路径转换时被截断。
        guard let components = URLComponents(url: file, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "file",
              components.host == nil || components.host == "" || components.host?.lowercased() == "localhost",
              !components.percentEncodedPath.contains("%00"),
              file.isFileURL,
              !file.path(percentEncoded: false).utf8.contains(0) else { throw Failure.notLocalFile }
        // O_NONBLOCK 避免误选 FIFO 时等待写入者；O_NOFOLLOW 不跟随最后一级符号链接。
        let descriptor = file.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else {
            throw errno == ELOOP ? Failure.notRegularFile : Failure.cannotRead
        }
        defer { _ = close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw Failure.cannotRead }
        // 检查打开后的描述符，避免先检查路径、再打开时被替换成目录或特殊文件。
        guard status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw Failure.notRegularFile }
        var bytes = [UInt8](repeating: 0, count: byteLimit)
        var count = 0
        while count < byteLimit {
            let readCount = bytes.withUnsafeMutableBytes { buffer in
                systemRead(descriptor, buffer.baseAddress!.advanced(by: count), byteLimit - count)
            }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw Failure.cannotRead
            }
            if readCount == 0 { break }
            count += readCount
        }
        return Snapshot(name: file.lastPathComponent, data: Data(bytes.prefix(count)),
                        observedFileSize: Int64(status.st_size))
    }

    private static func systemRead(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
#if canImport(Darwin)
        Darwin.read(descriptor, buffer, count)
#else
        Glibc.read(descriptor, buffer, count)
#endif
    }

    static func format(_ data: Data) -> String {
        let bytes = Array(data.prefix(byteLimit))
        return stride(from: 0, to: bytes.count, by: lineWidth).map { offset in
            let row = bytes[offset..<min(offset + lineWidth, bytes.count)]
            let hex = row.map { String(format: "%02X", $0) }.joined(separator: " ")
            let padding = String(repeating: " ", count: lineWidth * 3 - 1 - hex.count)
            let ascii = String(row.map { byte in
                byte >= 32 && byte <= 126 ? Character(UnicodeScalar(byte)) : "."
            })
            let tail = String(repeating: " ", count: lineWidth - row.count)
            return String(format: "%08X", offset) + "  " + hex + padding + "  |" + ascii + tail + "|"
        }.joined(separator: "\n")
    }
}
