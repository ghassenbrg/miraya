import XCTest
@testable import MirayaCore

final class RTCSignalingTests: XCTestCase {
    private let secure = "v=0\r\na=ice-ufrag:example\r\na=ice-pwd:longer-example\r\na=fingerprint:sha-256 AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB:AB\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
    func testRejectsUnencryptedAndNonMediaSDP() throws {
        XCTAssertNoThrow(try RTCSignaling.validateSDP(secure))
        XCTAssertThrowsError(try RTCSignaling.validateSDP(secure + "a=candidate:1 1 tcp 1 192.168.0.1 1234 typ host\r\n"))
        XCTAssertThrowsError(try RTCSignaling.validateSDP(secure.replacingOccurrences(of: "AB:AB", with: "AB")))
        XCTAssertThrowsError(try RTCSignaling.validateSDP(secure.replacingOccurrences(of: "UDP/TLS/RTP/SAVPF", with: "RTP/AVP")))
        XCTAssertThrowsError(try RTCSignaling.validateSDP(secure.replacingOccurrences(of: "m=video", with: "m=application")))
        XCTAssertThrowsError(try RTCSignaling.validateSDP(secure + String(repeating: "x", count: 32_768)))
        XCTAssertThrowsError(try RTCSignaling.validateSDP("v=0\r\nm=video 9 UDP/TLS/RTP/SAVPF 96\r\n"))
    }
    func testAllowsOnlyBoundedDirectUDPCandidates() throws {
        let candidate = "candidate:1 1 udp 2122260223 192.168.1.10 54321 typ host generation 0"
        XCTAssertNoThrow(try RTCSignaling.validateCandidate(candidate, mid: "0", index: 0))
        XCTAssertNoThrow(try RTCSignaling.validateCandidate(candidate.replacingOccurrences(of: "typ host", with: "typ prflx"), mid: "1", index: 1))
        for changed in [candidate.replacingOccurrences(of: " udp ", with: " tcp "), candidate.replacingOccurrences(of: "typ host", with: "typ relay"), candidate.replacingOccurrences(of: "54321", with: "65536"), candidate + "\r\ninjected"] {
            XCTAssertThrowsError(try RTCSignaling.validateCandidate(changed, mid: "0", index: 0))
        }
        XCTAssertThrowsError(try RTCSignaling.validateCandidate(candidate, mid: "0", index: 2))
    }
    func testStereoOpusPreservesPayloadAndVideoParameters() {
        let original = secure + "a=rtpmap:111 opus/48000/2\r\na=fmtp:111 minptime=10;useinbandfec=1;stereo=0\r\na=fmtp:96 packetization-mode=1\r\n"
        let modified = RTCSignaling.stereoOpus(original)
        XCTAssertTrue(modified.contains("minptime=10;useinbandfec=1;stereo=1;sprop-stereo=1;maxaveragebitrate=192000;usedtx=0"))
        XCTAssertTrue(modified.contains("a=fmtp:96 packetization-mode=1\r\n"))
        XCTAssertFalse(modified.contains("stereo=0"))
        XCTAssertEqual(RTCSignaling.stereoOpus(modified), modified)
    }
    func testDecoderLevelBoundsResolutionAndFrameRate() {
        let video = "a=rtpmap:96 H264/90000\r\na=fmtp:96 packetization-mode=1;profile-level-id=42e02a\r\n"
        XCTAssertEqual(RTCSignaling.h264ReceiveLimit(video).fps, 60)
        XCTAssertEqual(RTCSignaling.h264ReceiveLimit(video.replacingOccurrences(of: "2a", with: "28")).fps, 30)
        XCTAssertEqual(RTCSignaling.h264ReceiveLimit(video.replacingOccurrences(of: "2a", with: "1f")).width, 1280)
        XCTAssertEqual(RTCSignaling.h264ReceiveLimit("invalid").height, 720)
    }
}
