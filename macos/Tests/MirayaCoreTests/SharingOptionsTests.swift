import XCTest
@testable import MirayaCore

final class SharingOptionsTests: XCTestCase {
    func testCaptureRegionRejectsInvalidOrOutOfBoundsAreas() {
        XCTAssertTrue(CaptureRegion(x: 0, y: 0, width: 1440, height: 900).validated(displayWidth: 1440, displayHeight: 900))
        XCTAssertFalse(CaptureRegion(x: -1, y: 0, width: 100, height: 100).validated(displayWidth: 1440, displayHeight: 900))
        XCTAssertFalse(CaptureRegion(x: 1400, y: 0, width: 100, height: 100).validated(displayWidth: 1440, displayHeight: 900))
        XCTAssertFalse(CaptureRegion(x: 0, y: 0, width: .nan, height: 100).validated(displayWidth: 1440, displayHeight: 900))
        XCTAssertFalse(CaptureRegion(x: 0, y: 0, width: 1, height: 100).validated(displayWidth: 1440, displayHeight: 900))
    }
    func testDirectMediaOnlyAcceptsHTTPSWithoutEmbeddedCredentials() {
        XCTAssertTrue(DirectMedia.validRemoteURL("https://example.com/video.mp4?token=private"))
        for value in ["file:///etc/passwd", "http://example.com/video.mp4", "https://user:password@example.com/file", "javascript:alert(1)", "https://", "blob:https://example.com/id"] { XCTAssertFalse(DirectMedia.validRemoteURL(value), value) }
    }
    func testReadLimitsDoNotOverflowAndAllowExactEOF() {
        XCTAssertTrue(DirectMedia.validRead(offset: Int64.max, count: 1, size: Int64.max))
        XCTAssertFalse(DirectMedia.validRead(offset: -1, count: 1, size: 10))
        XCTAssertFalse(DirectMedia.validRead(offset: 11, count: 1, size: 10))
        XCTAssertFalse(DirectMedia.validRead(offset: 0, count: 32769, size: 10))
    }
    func testDiagnosticsAllowlistAndRetentionExcludePrivateFields() throws {
        var history = DiagnosticHistory(); let now = Date()
        history.record("sample", values: ["fps":30, "token":123, "rttMs":.infinity], now: now.addingTimeInterval(-73 * 3600))
        history.record("https://private.example/token", values: ["fps":1], now: now)
        history.record("sample", values: ["fps":24, "url":1, "path":2, "rttMs":.nan], now: now)
        XCTAssertEqual(history.events.count, 1)
        XCTAssertEqual(history.events.first?.values, ["fps":24])
        let json = String(data: try JSONEncoder().encode(history), encoding: .utf8)!
        XCTAssertFalse(json.contains("token")); XCTAssertFalse(json.contains("url")); XCTAssertFalse(json.contains("path"))
        for _ in 0..<2100 { history.record("sharing", now: now) }
        XCTAssertEqual(history.events.count, 2000)
    }
}
