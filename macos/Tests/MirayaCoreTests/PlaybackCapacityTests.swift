import XCTest
@testable import MirayaCore

final class PlaybackCapacityTests: XCTestCase {
    func testDetailPriorityLowersFrameRateWithoutShrinkingPicture() {
        var capacity = PlaybackCapacity(maximumFPS: 30, preservesDetail: true)
        _ = capacity.observe(frames: 1, drops: 0, inputFPS: 30, targetFPS: 30, paused: false, now: 0)
        XCTAssertTrue(capacity.observe(frames: 16, drops: 15, inputFPS: 30, targetFPS: 30, paused: false, now: 1))
        XCTAssertEqual(capacity.maximumFPS, 24); XCTAssertEqual(capacity.scale, 1)
        XCTAssertFalse(capacity.observe(frames: 31, drops: 30, inputFPS: 30, targetFPS: 24, paused: false, now: 2))
        XCTAssertFalse(capacity.observe(frames: 46, drops: 45, inputFPS: 30, targetFPS: 24, paused: false, now: 3))
        XCTAssertTrue(capacity.observe(frames: 61, drops: 60, inputFPS: 30, targetFPS: 24, paused: false, now: 4))
        XCTAssertEqual(capacity.maximumFPS, 15); XCTAssertEqual(capacity.scale, 1)
        XCTAssertFalse(capacity.observe(frames: 76, drops: 90, inputFPS: 30, targetFPS: 15, paused: false, now: 8))
        XCTAssertEqual(capacity.scale, 1)
    }
    func testSlowTVFallsBackToThirtyAndStaysStable() {
        var capacity = PlaybackCapacity(maximumFPS: 60)
        XCTAssertEqual(capacity.maximumFPS, 30)
        XCTAssertFalse(capacity.observe(frames: 1, drops: 0, inputFPS: 60, targetFPS: 30, paused: false, now: 0))
        for second in 1...4 { XCTAssertFalse(capacity.observe(frames: 1 + second * 30, drops: 0, inputFPS: 60, targetFPS: 30, paused: false, now: Double(second))) }
        XCTAssertTrue(capacity.observe(frames: 151, drops: 0, inputFPS: 60, targetFPS: 30, paused: false, now: 5))
        XCTAssertEqual(capacity.maximumFPS, 60)
        XCTAssertTrue(capacity.observe(frames: 186, drops: 25, inputFPS: 60, targetFPS: 60, paused: false, now: 6))
        XCTAssertEqual(capacity.maximumFPS, 30)
        for second in 7...12 { XCTAssertFalse(capacity.observe(frames: 186 + (second - 6) * 30, drops: 25, inputFPS: 60, targetFPS: 30, paused: false, now: Double(second))) }
        XCTAssertEqual(capacity.scale, 1)
    }
    func testStaticAndPausedScreensDoNotCauseDowngrades() {
        var capacity = PlaybackCapacity(maximumFPS: 60)
        _ = capacity.observe(frames: 1, drops: 0, inputFPS: 1, targetFPS: 60, paused: false, now: 0)
        XCTAssertFalse(capacity.observe(frames: 2, drops: 40, inputFPS: 1, targetFPS: 60, paused: false, now: 1))
        XCTAssertFalse(capacity.observe(frames: 2, drops: 80, inputFPS: 60, targetFPS: 60, paused: true, now: 2))
        XCTAssertEqual(capacity.maximumFPS, 30)
    }
    func testHealthyTVKeepsTheHigherRateAfterOneProbe() {
        var capacity = PlaybackCapacity(maximumFPS: 60)
        _ = capacity.observe(frames: 1, drops: 0, inputFPS: 60, targetFPS: 30, paused: false, now: 0)
        for second in 1...5 { _ = capacity.observe(frames: 1 + second * 30, drops: 0, inputFPS: 60, targetFPS: 30, paused: false, now: Double(second)) }
        XCTAssertFalse(capacity.observe(frames: 211, drops: 0, inputFPS: 60, targetFPS: 60, paused: false, now: 6))
        XCTAssertEqual(capacity.maximumFPS, 60)
    }
    func testPersistentThirtyFPSOverloadReducesPixelsWithCooldownAndFloor() {
        var capacity = PlaybackCapacity(maximumFPS: 30)
        _ = capacity.observe(frames: 1, drops: 0, inputFPS: 30, targetFPS: 30, paused: false, now: 0)
        XCTAssertTrue(capacity.observe(frames: 16, drops: 15, inputFPS: 30, targetFPS: 30, paused: false, now: 1))
        XCTAssertEqual(capacity.scale, 2.0 / 3)
        XCTAssertFalse(capacity.observe(frames: 31, drops: 30, inputFPS: 30, targetFPS: 30, paused: false, now: 2))
        XCTAssertTrue(capacity.observe(frames: 61, drops: 60, inputFPS: 30, targetFPS: 30, paused: false, now: 4))
        XCTAssertEqual(capacity.scale, 0.5)
        XCTAssertFalse(capacity.observe(frames: 91, drops: 90, inputFPS: 30, targetFPS: 30, paused: false, now: 6))
    }
}
