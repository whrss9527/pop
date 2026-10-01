import XCTest
@testable import Pop

final class DiskSpeedTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "DiskSpeedTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func leftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
    }

    func testMeasuresWritingAndReading() throws {
        var passes: [DiskSpeed.Pass] = []
        var last: DiskSpeed.Progress?
        let speeds = try DiskSpeed.measure(in: folder, size: 24_000_000, chunk: 4 << 20) { progress in
            if passes.last != progress.pass {
                passes.append(progress.pass)
            }
            last = progress
        }
        XCTAssertGreaterThan(speeds.write, 0)
        XCTAssertGreaterThan(speeds.read, 0)
        // 先写后读，读完正好是写的那么多
        XCTAssertEqual(passes, [.write, .read])
        XCTAssertEqual(last?.done, 24_000_000)
        XCTAssertEqual(last?.total, 24_000_000)
        // 测试文件删掉了
        XCTAssertEqual(try leftovers(), [])
    }

    func testStoppingRemovesTheTestFile() throws {
        final class Chunks {
            var count = 0
        }
        let chunks = Chunks()
        XCTAssertThrowsError(try DiskSpeed.measure(in: folder, size: 64_000_000, chunk: 4 << 20, isCancelled: { chunks.count >= 3 }) { _ in chunks.count += 1 }) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(try leftovers(), [])
        // 写不了的地方
        XCTAssertThrowsError(try DiskSpeed.measure(in: folder.appending(path: "没有这个文件夹"), size: 1_000_000)) { error in
            XCTAssertTrue((error as? DiskSpeed.Failure)?.message.hasPrefix("这里写不了文件") == true, "\(error)")
        }
    }

    func testMeterKeepsAboutHalfASecond() {
        var meter = DiskSpeed.Meter(pass: .write, total: 100)
        let start = ProcessInfo.processInfo.systemUptime
        _ = meter.add(10, at: start + 0.1)
        _ = meter.add(10, at: start + 0.2)
        let progress = meter.add(10, at: start + 1.0)
        XCTAssertEqual(progress.done, 30)
        XCTAssertEqual(progress.total, 100)
        // 最近半秒里只有一块：从上一块（0.2 秒）算起
        XCTAssertEqual(progress.speed, 10 / 0.8, accuracy: 0.5)
    }

    func testDescribesVolumesAndSpeeds() throws {
        XCTAssertEqual(DiskSpeed.speedText(2_834_400_000), "2,834 MB/s")
        XCTAssertEqual(DiskSpeed.speedText(86_440_000), "86.4 MB/s")
        let external = DiskSpeedPlugin.demoVolumes()[1]
        XCTAssertTrue(DiskSpeed.describe(external).hasPrefix("ExFAT · 外接 · 可用 "), DiskSpeed.describe(external))
        XCTAssertEqual(DiskSpeed.folder(for: DiskSpeedPlugin.demoVolumes()[0]), FileManager.default.temporaryDirectory)
        XCTAssertEqual(DiskSpeed.folder(for: external), URL(fileURLWithPath: "/Volumes/T7 Shield"))

        // 这台 Mac 的启动磁盘一定在，排在最前面
        let volumes = DiskSpeed.volumes()
        let startup = try XCTUnwrap(volumes.first)
        XCTAssertTrue(startup.isStartup)
        XCTAssertGreaterThan(startup.total, 0)
        XCTAssertEqual(DiskSpeed.volume(containing: folder)?.isStartup, true)
    }

    @MainActor
    func testCardRunsAndStops() async throws {
        defer { UserDefaults.standard.removeObject(forKey: DiskSpeedModel.sizeKey) }
        let volumes = DiskSpeedPlugin.demoVolumes()
        let folder = folder!
        let model = DiskSpeedModel(volumes: volumes, selecting: volumes[1].url, folderFor: { _ in folder }, bytesOverride: 16_000_000)
        XCTAssertEqual(model.selected?.name, "T7 Shield")
        XCTAssertNil(model.spaceProblem)
        XCTAssertNil(model.resultText)

        model.start()
        XCTAssertTrue(model.isRunning)
        await model.waitUntilDone()
        XCTAssertEqual(model.phase, .done)
        XCTAssertGreaterThan(model.writeSpeed ?? 0, 0)
        XCTAssertGreaterThan(model.readSpeed ?? 0, 0)
        XCTAssertEqual(model.fraction, 1)
        let text = try XCTUnwrap(model.resultText)
        XCTAssertTrue(text.hasPrefix("T7 Shield（ExFAT · 外接 · "), text)
        XCTAssertTrue(text.contains("\n写入 ") && text.contains("\n读取 ") && text.hasSuffix("测试文件 16 MB"), text)
        XCTAssertEqual(try leftovers(), [])

        // 停下：回到没测的样子
        model.start()
        model.stop()
        await model.waitUntilDone()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.writeSpeed)
        XCTAssertEqual(try leftovers(), [])

        // 记住测试文件的大小；空间不够时不让测
        model.size = .large
        XCTAssertEqual(DiskSpeedModel(volumes: volumes).size, .large)
        let tiny = DiskSpeed.Volume(url: URL(fileURLWithPath: "/Volumes/Tiny"), name: "Tiny", format: "MS-DOS (FAT32)", isInternal: false,
                                    isRemovable: true, isLocal: true, total: 1_000_000_000, available: 500_000_000)
        let full = DiskSpeedModel(volumes: [tiny])
        XCTAssertEqual(full.spaceProblem, "「Tiny」上的空间不够，换小一点的测试文件")
        full.start()
        XCTAssertEqual(full.phase, .idle)
    }

    @MainActor
    func testDemoAndPlugin() {
        let model = DiskSpeedModel(volumes: DiskSpeedPlugin.demoVolumes())
        model.showResult(write: 921_400_000, read: 1_012_800_000)
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.selected?.name, "Macintosh HD")
        XCTAssertTrue(DiskSpeedPlugin().info.canHandle(.empty))
    }
}
