import XCTest
import MirayaCore

final class MediaFileProviderTests: XCTestCase {
    func testOnlySelectedFileRangesAreReadableAndStopRevokesAccess() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([10,20,30,40,50]).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let files = MediaFileProvider(); let asset = try files.authorize(url)
        let id = asset["id"] as! String
        func read(_ id: String, offset: Int, count: Int) -> [String: Any] {
            let done = expectation(description: "range reply"); var reply: [String: Any] = [:]
            files.respond(["request":UUID().uuidString, "id":id, "offset":offset, "count":count]) { reply = $0; done.fulfill() }
            wait(for: [done], timeout: 2); return reply
        }
        XCTAssertEqual(Data(base64Encoded: read(id, offset: 1, count: 3)["data"] as! String), Data([20,30,40]))
        XCTAssertEqual(read(id, offset: 5, count: 2)["data"] as? String, "")
        XCTAssertNotNil(read(url.path, offset: 0, count: 5)["error"])
        XCTAssertNotNil(read(id, offset: -1, count: 5)["error"])
        XCTAssertNotNil(read(id, offset: 0, count: 32769)["error"])
        files.close(); XCTAssertNotNil(read(id, offset: 0, count: 5)["error"])
    }
}
