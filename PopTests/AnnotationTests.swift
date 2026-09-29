import AppKit
import XCTest
@testable import Pop

@MainActor
final class AnnotationTests: XCTestCase {
    /// 100×60 像素的白图，按 2 倍屏算是 50×30 点
    private func makeModel() throws -> AnnotationModel {
        let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 60))
        return AnnotationModel(image: try XCTUnwrap(context.makeImage()), pointSize: CGSize(width: 50, height: 30))
    }

    func testDrawingAndUndo() throws {
        let model = try makeModel()
        model.tool = .rectangle
        model.begin(at: CGPoint(x: 10, y: 10))
        model.drag(to: CGPoint(x: 40, y: 20))
        model.end()
        XCTAssertEqual(model.annotations.count, 1)
        XCTAssertEqual(model.annotations.first?.bounds, CGRect(x: 10, y: 10, width: 30, height: 10))

        // 手抖点了一下：不算一笔
        model.tool = .arrow
        model.begin(at: CGPoint(x: 5, y: 5))
        model.end()
        XCTAssertEqual(model.annotations.count, 1)

        // 序号自动加一
        model.tool = .counter
        model.begin(at: CGPoint(x: 5, y: 5))
        model.begin(at: CGPoint(x: 15, y: 5))
        XCTAssertEqual(model.annotations.suffix(2).map(\.kind), [.counter(1), .counter(2)])

        // 文字：点一下开始输入，回车（或者点别处）完成；空的不要
        model.tool = .text
        model.begin(at: CGPoint(x: 20, y: 20))
        model.textDraft = "注意"
        model.commitText()
        XCTAssertEqual(model.annotations.last?.kind, .text("注意"))
        model.begin(at: CGPoint(x: 30, y: 20))
        model.commitText()
        XCTAssertEqual(model.annotations.count, 4)

        model.undo()
        XCTAssertEqual(model.annotations.count, 3)
        XCTAssertTrue(model.canUndo)
    }

    func testRenderingKeepsPixelSizeAndDrawsStrokes() throws {
        let model = try makeModel()
        model.color = .red
        model.lineWidth = 4
        model.tool = .rectangle
        model.begin(at: CGPoint(x: 10, y: 10))
        model.drag(to: CGPoint(x: 40, y: 20))
        model.end()
        model.tool = .counter
        model.begin(at: CGPoint(x: 45, y: 25))
        model.tool = .mosaic
        model.begin(at: CGPoint(x: 0, y: 0))
        model.drag(to: CGPoint(x: 8, y: 8))
        model.end()

        let png = try XCTUnwrap(model.renderPNG())
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, 100)
        XCTAssertEqual(image.pixelsHigh, 60)
        // 方框左边那条线：x = 10 点 = 20 像素，竖直方向在中间
        let stroke = try XCTUnwrap(image.colorAt(x: 20, y: 30)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(stroke.redComponent, 0.8)
        XCTAssertLessThan(stroke.greenComponent, 0.5)
        // 方框里面还是白的
        let inside = try XCTUnwrap(image.colorAt(x: 50, y: 30)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(inside.greenComponent, 0.9)
    }

    func testRenderingWithBackground() throws {
        let model = try makeModel()
        model.background = .sky
        // 四周各留 24 点
        XCTAssertEqual(model.outputSize, CGSize(width: 98, height: 78))
        let png = try XCTUnwrap(model.renderPNG())
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, 196)
        XCTAssertEqual(image.pixelsHigh, 156)
        // 角上是渐变背景，中间是截图（白的）
        let corner = try XCTUnwrap(image.colorAt(x: 2, y: 2)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(corner.greenComponent, 0.8)
        let middle = try XCTUnwrap(image.colorAt(x: 98, y: 78)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(middle.redComponent, 0.95)
        XCTAssertGreaterThan(middle.greenComponent, 0.95)
        // 不加背景时还是原图大小
        model.background = nil
        XCTAssertEqual(model.outputSize, CGSize(width: 50, height: 30))
    }

    func testArrowHeadFollowsDirection() {
        let path = Annotation.arrowPath(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 4)
        let bounds = path.boundingRect
        // 箭头的两撇在终点左边，上下对称
        XCTAssertEqual(bounds.maxX, 100, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, -bounds.maxY, accuracy: 0.001)
        XCTAssertGreaterThan(bounds.height, 10)
    }
}
