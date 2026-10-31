import XCTest
@testable import MirayaCore

final class PairingSessionTests: XCTestCase {
    func testSharedAndroidCommitmentAndCodeVector() {
        let nonce = String(repeating: "01", count: 32)
        XCTAssertEqual(PairingSession.commitment(nonce: nonce), "481a82c900bb670a336dbaf904a506ffea2f3763eafe716380d0c6c70bad88c2")
        let code = PairingSession.code(fingerprint: String(repeating: "AB", count: 32), clientID: "12345678-1234-1234-1234-123456789ABC", senderNonce: nonce, receiverNonce: String(repeating: "02", count: 32))
        XCTAssertEqual(code, "447474")
    }
    func testCodeBindsCertificateClientAndBothNonces() {
        let fingerprint = String(repeating: "ab", count: 32)
        let client = "12345678-1234-1234-1234-123456789abc"
        let sender = String(repeating: "01", count: 32), receiver = String(repeating: "02", count: 32)
        let code = PairingSession.code(fingerprint: fingerprint, clientID: client, senderNonce: sender, receiverNonce: receiver)
        for changed in [PairingSession.code(fingerprint: String(repeating: "cd", count: 32), clientID: client, senderNonce: sender, receiverNonce: receiver),
                        PairingSession.code(fingerprint: fingerprint, clientID: "different", senderNonce: sender, receiverNonce: receiver),
                        PairingSession.code(fingerprint: fingerprint, clientID: client, senderNonce: receiver, receiverNonce: receiver),
                        PairingSession.code(fingerprint: fingerprint, clientID: client, senderNonce: sender, receiverNonce: sender)] {
            XCTAssertNotEqual(code, changed)
        }
    }
    func testNonceEntropyAndStrictEncoding() {
        let values = (0..<100).map { _ in PairingSession.nonce() }
        XCTAssertEqual(Set(values).count, 100)
        XCTAssertTrue(values.allSatisfy(PairingSession.validHex))
        XCTAssertFalse(PairingSession.validHex(String(repeating: "G", count: 64)))
        XCTAssertFalse(PairingSession.validHex("123456"))
    }
}
