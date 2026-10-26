import XCTest
@testable import MirayaCore

final class KeychainVaultTests: XCTestCase {
    func testMultipleTVsPersistUpdateAndRevokeIndependently() throws {
        // Real, disposable Keychain items catch macOS-specific query semantics;
        // existing application credentials are never read or changed.
        let service = "app.miraya.test." + UUID().uuidString
        let vault = KeychainVault(service: service)
        defer { try? vault.remove(account: "lounge"); try? vault.remove(account: "bedroom") }
        XCTAssertTrue(try vault.records().isEmpty)
        try vault.save(Data("first".utf8), account: "lounge")
        try vault.save(Data("second".utf8), account: "bedroom")
        let reopened = KeychainVault(service: service)
        XCTAssertEqual(Set(try reopened.records()), Set([Data("first".utf8), Data("second".utf8)]))
        try reopened.save(Data("updated".utf8), account: "lounge")
        XCTAssertEqual(try vault.read(account: "lounge"), Data("updated".utf8))
        XCTAssertEqual(try vault.records().count, 2)
        try reopened.remove(account: "lounge")
        XCTAssertEqual(try vault.records(), [Data("second".utf8)])
        XCTAssertNil(try vault.read(account: "lounge"))
        try vault.remove(account: "lounge")
    }
}
