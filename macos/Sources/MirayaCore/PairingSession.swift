import Foundation
import CryptoKit

/// A short authentication string bound to this TLS certificate and two fresh
/// nonces. Commit to the sender nonce before the receiver reveals its nonce;
/// otherwise an active peer could search offline for matching short codes.
public enum PairingSession {
    public static let method = "sas6-v1"
    public static func nonce() -> String {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).map { String(format: "%02x", $0) }.joined() }
    }
    public static func validHex(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    public static func commitment(nonce: String) -> String {
        digest("Miraya sender commitment v1\n" + nonce).map { String(format: "%02x", $0) }.joined()
    }
    public static func code(fingerprint: String, clientID: String, senderNonce: String, receiverNonce: String) -> String {
        let bytes = digest(["Miraya pairing SAS v1", fingerprint.lowercased(), clientID.lowercased(), senderNonce, receiverNonce].joined(separator: "\n"))
        let value = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return String(format: "%06u", value % 1_000_000)
    }
    private static func digest(_ value: String) -> [UInt8] { Array(SHA256.hash(data: Data(value.utf8))) }
}
