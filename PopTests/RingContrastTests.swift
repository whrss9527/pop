import XCTest
@testable import Pop

final class RingContrastTests: XCTestCase {
    private var backgrounds: [ColorValue] {
        [0.0, 127.5, 255.0].flatMap { red in
            [0.0, 127.5, 255.0].flatMap { green in
                [0.0, 127.5, 255.0].map { blue in ColorValue(red: red, green: green, blue: blue) }
            }
        }
    }

    private func gray(_ level: Double) -> ColorValue {
        ColorValue(red: level * 255, green: level * 255, blue: level * 255)
    }

    private func blend(_ color: ColorValue, opacity: Double, over background: ColorValue) -> ColorValue {
        ColorValue(red: color.red * opacity + background.red * (1 - opacity),
                   green: color.green * opacity + background.green * (1 - opacity),
                   blue: color.blue * opacity + background.blue * (1 - opacity))
    }

    func testCaptionsRemainReadableAcrossWallpaperColorsAndStates() {
        for isDark in [false, true] {
            let palette = RingPalette(isDark: isDark)
            for wallpaper in backgrounds {
                let surface = blend(gray(palette.surfaceLevel), opacity: RingPalette.surfaceOpacity, over: wallpaper)
                for opacity in [1, RingPalette.mutedOpacity] {
                    let foreground = blend(gray(palette.foregroundLevel), opacity: opacity, over: surface)
                    XCTAssertGreaterThanOrEqual(ColorContrast.ratio(foreground, surface), 4.5)
                }
            }
        }
    }

    func testHoveredAndCommittedIconsKeepContrastWithAnyAccentColor() {
        for isDark in [false, true] {
            let palette = RingPalette(isDark: isDark)
            for wallpaper in backgrounds {
                let surface = blend(gray(palette.surfaceLevel), opacity: RingPalette.surfaceOpacity, over: wallpaper)
                for accent in backgrounds {
                    for opacity in [0.16, 0.28] {
                        let highlighted = blend(accent, opacity: opacity, over: surface)
                        XCTAssertGreaterThanOrEqual(ColorContrast.ratio(gray(palette.foregroundLevel), highlighted), 4.5)
                    }
                }
                for tint in [gray(0), gray(1)] {
                    let hovered = blend(tint, opacity: 0.06, over: surface)
                    let muted = blend(gray(palette.foregroundLevel), opacity: RingPalette.mutedOpacity, over: hovered)
                    XCTAssertGreaterThanOrEqual(ColorContrast.ratio(muted, hovered), 4.5)
                }
            }
        }
    }
}
