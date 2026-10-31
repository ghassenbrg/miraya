import XCTest
@testable import MirayaCore

final class WireTests: XCTestCase {
    func testFragmentedAndCoalescedPackets() throws {
        let payload = Data(#"{"op":"ping","nonce":23}"#.utf8)
        let wire = try Packet(type: .control, pts: 12345678, sequence: 3, payload: payload).encoded()
        var parser = PacketParser(); var packets: [Packet] = []
        for byte in wire { packets += try parser.append(Data([byte])) }
        XCTAssertEqual(packets.count, 1); XCTAssertEqual(packets[0].pts, 12345678)
        XCTAssertEqual(packets[0].sequence, 3); XCTAssertEqual(try packets[0].control["op"] as? String, "ping")
        XCTAssertEqual(try parser.append(wire + wire).count, 2)
    }
    func testRejectsLengthBeforePayloadArrives() throws {
        var wire = try Packet(type: .video, payload: Data([1])).encoded()
        wire[8] = 0xff
        var parser = PacketParser(); XCTAssertThrowsError(try parser.append(Data(wire.prefix(24))))
    }
    func testReservedAndFlagBitsRejected() throws {
        for index in [0, 4, 5, 6, 7] {
            var wire = try Packet(type: .control, payload: Data([1])).encoded()
            wire[index] = 0xff
            var parser = PacketParser(); XCTAssertThrowsError(try parser.append(wire))
        }
    }
    func testVideoPayloadAndBoundary() throws {
        let payload = Data(repeating: 0x7f, count: 4_194_304)
        let wire = try Packet(type: .video, flags: 1, pts: UInt64(Int64.max), sequence: .max, payload: payload).encoded()
        var parser = PacketParser(); var result: [Packet] = []
        for start in stride(from: 0, to: wire.count, by: 60_000) { result += try parser.append(Data(wire[start..<min(start+60_000,wire.count)])) }
        XCTAssertEqual(result.first?.payload, payload); XCTAssertEqual(result.first?.pts, UInt64(Int64.max))
        XCTAssertThrowsError(try Packet(type: .audio, payload: Data([1,2])).encoded())
        XCTAssertThrowsError(try Packet(type: .control, payload: Data()).encoded())
    }
    func testRejectsTimestampHighBitBeforePayload() throws {
        XCTAssertThrowsError(try Packet(type: .video, pts: UInt64(Int64.max) + 1, payload: Data([1])).encoded())
        var wire = try Packet(type: .video, payload: Data([1])).encoded()
        wire[12] = 0x80
        var parser = PacketParser()
        XCTAssertThrowsError(try parser.append(Data(wire.prefix(24))))
    }
    func testPairingCodeAndScaling() {
        XCTAssertEqual(PairingCode.normalize("012 345"), "012345")
        XCTAssertNil(PairingCode.normalize("A1B2-C3D4-E5F6-0123")); XCTAssertNil(PairingCode.normalize("12345"))
        XCTAssertEqual(VideoSize.fit(width: 3840, height:2160, maxWidth:1920,maxHeight:1080), VideoSize(width:1920,height:1080))
        let portrait = VideoSize.fit(width:1080,height:1920,maxWidth:1920,maxHeight:1080)
        XCTAssertEqual(portrait.height,1080); XCTAssertEqual(portrait.width,606)
    }
    func testDeterministicWireVector() throws {
        let bytes = try Packet(type: .video, flags: 1, pts: 0x0102030405060708, sequence: 0x0a0b0c0d, payload: Data([0,0,0,1,0x65])).encoded()
        XCTAssertEqual(bytes.map { String(format:"%02x",$0) }.joined(), "4d525931030100000000000501020304050607080a0b0c0d0000000165")
    }
}
