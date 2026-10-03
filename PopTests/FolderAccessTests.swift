import XCTest
@testable import Pop

final class FolderAccessTests: XCTestCase {
    func testCoveredByAllowedFolders() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        XCTAssertTrue(FolderAccess.isCovered(URL(fileURLWithPath: "/Users/someone/Downloads/截图.png"), by: [home]))
        XCTAssertTrue(FolderAccess.isCovered(URL(fileURLWithPath: "/Users/someone", isDirectory: true), by: [home]))
        // 名字开头一样的别的文件夹不算
        XCTAssertFalse(FolderAccess.isCovered(URL(fileURLWithPath: "/Users/someone2/截图.png"), by: [home]))
        XCTAssertFalse(FolderAccess.isCovered(URL(fileURLWithPath: "/Volumes/U盘/截图.png"), by: [home]))
        XCTAssertFalse(FolderAccess.isCovered(URL(fileURLWithPath: "/Users/someone/截图.png"), by: []))
        XCTAssertTrue(FolderAccess.isCovered(URL(fileURLWithPath: "/Volumes/U盘/截图.png"), by: [URL(fileURLWithPath: "/")]))
        // 带「..」的路径按实际位置算
        XCTAssertFalse(FolderAccess.isCovered(URL(fileURLWithPath: "/Users/someone/../other/截图.png"), by: [home]))
    }

    /// 允许的是 /tmp 这样的符号链接，文件路径是它指向的 /private/tmp，也算在里面
    func testSymlinkedFolders() {
        let file = URL(fileURLWithPath: "/private/tmp/截图.png")
        XCTAssertTrue(FolderAccess.isCovered(file, by: [URL(fileURLWithPath: "/tmp", isDirectory: true)]))
    }

    /// GitHub 版没开沙盒，选中什么文件都不用先允许
    @MainActor func testGitHubEditionNeverAsks() {
        XCTAssertEqual(FolderAccess.shared.needingAccess([URL(fileURLWithPath: NSTemporaryDirectory())]), [])
    }
}
