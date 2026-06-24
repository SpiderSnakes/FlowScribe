// FlowScribeCore/Tests/FlowScribeCoreTests/AmbianceTests.swift
import XCTest
@testable import FlowScribeCore

final class AmbianceTests: XCTestCase {
    // --- Animation policy (cahier §4) ---
    func test_reduceMotion_disablesEverything() {
        for i in AmbianceIntensity.allCases {
            for s in [AmbianceSurface.onboarding, .hud, .appWindow] {
                XCTAssertFalse(ambianceAnimates(intensity: i, surface: s, reduceMotion: true, windowActive: true))
            }
        }
    }
    func test_hud_alwaysAnimates_unlessReduceMotion() {
        for i in AmbianceIntensity.allCases {
            XCTAssertTrue(ambianceAnimates(intensity: i, surface: .hud, reduceMotion: false, windowActive: false))
        }
    }
    func test_onboarding_staticOnlyInDiscret() {
        XCTAssertFalse(ambianceAnimates(intensity: .discret, surface: .onboarding, reduceMotion: false, windowActive: true))
        XCTAssertTrue(ambianceAnimates(intensity: .equilibre, surface: .onboarding, reduceMotion: false, windowActive: true))
        XCTAssertTrue(ambianceAnimates(intensity: .showcase, surface: .onboarding, reduceMotion: false, windowActive: true))
    }
    func test_appWindow_equilibre_pausesWhenInactive() {
        XCTAssertTrue(ambianceAnimates(intensity: .equilibre, surface: .appWindow, reduceMotion: false, windowActive: true))
        XCTAssertFalse(ambianceAnimates(intensity: .equilibre, surface: .appWindow, reduceMotion: false, windowActive: false))
    }
    func test_appWindow_discret_neverAnimates() {
        XCTAssertFalse(ambianceAnimates(intensity: .discret, surface: .appWindow, reduceMotion: false, windowActive: true))
    }
    func test_appWindow_showcase_animatesEvenInactive() {
        XCTAssertTrue(ambianceAnimates(intensity: .showcase, surface: .appWindow, reduceMotion: false, windowActive: false))
    }
    // --- Palette mapping ---
    func test_rgba_hexDecodes() {
        let c = RGBA(hex: 0x5B8DEF)
        XCTAssertEqual(c.r, 0x5B / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.g, 0x8D / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.b, 0xEF / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.a, 1, accuracy: 0.001)
    }
    func test_eachPalette_hasNonNeutralAccents_andDistinctBase() {
        for p in AmbiancePalette.allCases {
            let c = p.colors
            XCTAssertNotEqual(c.base, c.accentPrimary)
            XCTAssertNotEqual(c.accentPrimary, c.accentSecondary)
            XCTAssertEqual(c.hairline.a, 0.14, accuracy: 0.001)   // neutre commun
        }
    }
}
