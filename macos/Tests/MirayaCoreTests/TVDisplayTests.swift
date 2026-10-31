import XCTest
@testable import MirayaCore

final class TVDisplayTests: XCTestCase {
    private let valid: [String: Any] = ["width":1920, "height":1080, "panelWidth":3840, "panelHeight":2160, "refreshRate":59.94, "mode":"fit", "edgeInsetPercent":5]
    func testPanelModeAndAppViewportRemainDistinct() throws {
        let display = try XCTUnwrap(TVDisplay(json: valid))
        XCTAssertEqual(display.width, 1920); XCTAssertEqual(display.panelWidth, 3840)
        XCTAssertEqual(display.mode, .fit); XCTAssertEqual(display.edgeInsetPercent, 5)
    }
    func testInvalidCapabilitiesAreIgnored() {
        for (key, value) in [("width", -1 as Any), ("width", 1920.5 as Any), ("width", true as Any), ("panelWidth", 20000 as Any), ("refreshRate", Double.nan as Any), ("mode", "execute" as Any), ("edgeInsetPercent", 11 as Any), ("edgeInsetPercent", 0.5 as Any)] {
            var json = valid; json[key] = value
            XCTAssertNil(TVDisplay(json: json), "Invalid \(key) accepted")
        }
    }
}
