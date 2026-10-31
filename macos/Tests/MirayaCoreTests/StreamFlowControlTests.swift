import XCTest
@testable import MirayaCore

final class StreamFlowControlTests: XCTestCase {
    func testIdleDesktopResumesWithoutFalseStall() {
        var flow = StreamFlowControl()
        flow.sent(pts: 1_000_000, now: 0)
        flow.acknowledge(pts: 1_000_000, now: 0.1)
        XCTAssertFalse(flow.stalled(now: 60))
        flow.sent(pts: 61_000_000, now: 60)
        XCTAssertFalse(flow.stalled(now: 60.1))
        XCTAssertTrue(flow.shouldEncode(bufferedBytes: 0, now: 60.1))
    }
    func testDecoderRecoveryDoesNotStarveKeyframes() {
        var flow = StreamFlowControl()
        flow.sent(pts: 0, now: 0)
        XCTAssertTrue(flow.shouldEncode(bufferedBytes: 0, now: 1))
        XCTAssertFalse(flow.shouldEncode(bufferedBytes: 0, now: 1.1))
        XCTAssertTrue(flow.shouldEncode(bufferedBytes: 0, now: 1.25))
        XCTAssertFalse(flow.shouldEncode(bufferedBytes: 256_000, now: 2))
        flow.acknowledge(pts: 0, now: 2)
        XCTAssertTrue(flow.shouldEncode(bufferedBytes: 0, now: 2.01))
        XCTAssertFalse(flow.stalled(now: 100))
    }
    func testOutstandingStallAndInvalidAcknowledgements() {
        var flow = StreamFlowControl()
        flow.sent(pts: 100, now: 0)
        flow.acknowledge(pts: 101, now: 7)
        XCTAssertTrue(flow.stalled(now: 8.1))
        flow.acknowledge(pts: 100, now: 9)
        flow.sent(pts: 200, now: 20)
        flow.acknowledge(pts: 100, now: 27) // duplicate stats must not mask a stall
        XCTAssertTrue(flow.stalled(now: 28.1))
    }
    func testProgressingButDelayedTCPIsThrottledWithoutDeadlock() {
        var flow = StreamFlowControl()
        flow.sent(pts: 1_000_000, now: 0)
        flow.acknowledge(pts: 1_000_000, now: 0.1)
        flow.sent(pts: 2_000_000, now: 1)
        XCTAssertTrue(flow.shouldEncode(bufferedBytes: 0, now: 1.1))
        flow.acknowledge(pts: 1_100_000, now: 1.2)
        XCTAssertFalse(flow.shouldEncode(bufferedBytes: 0, now: 1.21))
        XCTAssertFalse(flow.congested(now: 1.2))
        XCTAssertTrue(flow.congested(now: 1.8))
        XCTAssertTrue(flow.shouldEncode(bufferedBytes: 0, now: 1.8))
        flow.acknowledge(pts: 2_000_000, now: 1.9)
        XCTAssertFalse(flow.congested(now: 1.9))
        XCTAssertTrue(flow.shouldEncode(bufferedBytes: 0, now: 1.91))
    }
    private func packet(_ type: PacketType, size: Int = 100, key: Bool = false) -> Packet {
        Packet(type: type, flags: key ? 1 : 0, payload: Data(repeating: 0, count: size))
    }
    func testSceneChangeFrameDoesNotDisconnect() {
        var queue = MediaSendQueue()
        XCTAssertFalse(queue.append(packet(.video, size: 2_000_000, key: true), now: 0))
        XCTAssertEqual(queue.pop()?.packet.payload.count, 2_000_000)
    }
    func testCongestionPreservesControlAndConfigurationAndWaitsForIDR() {
        var queue = MediaSendQueue()
        queue.append(packet(.control), now: 0)
        queue.append(packet(.videoConfig), now: 0)
        queue.append(packet(.video, key: true), now: 0)
        XCTAssertTrue(queue.append(packet(.video), now: 0.3))
        XCTAssertEqual(queue.pop()?.packet.type, .control)
        XCTAssertEqual(queue.pop()?.packet.type, .videoConfig)
        XCTAssertNil(queue.pop())
        XCTAssertTrue(queue.needsKeyframe)
        queue.append(packet(.video), now: 0.31)
        XCTAssertNil(queue.pop())
        queue.append(packet(.video, key: true), now: 0.32)
        XCTAssertFalse(queue.needsKeyframe)
        queue.append(packet(.video), now: 0.33)
        XCTAssertEqual(queue.pop()?.packet.flags, 1)
        XCTAssertEqual(queue.pop()?.packet.flags, 0)
        XCTAssertEqual(queue.byteCount, 0)
    }
    func testOverflowRetainsIncomingKeyframeAndBoundsMemory() {
        var queue = MediaSendQueue()
        queue.append(packet(.video, size: 400_000), now: 0)
        XCTAssertTrue(queue.append(packet(.video, size: 400_000, key: true), now: 0.1))
        XCTAssertEqual(queue.pop()?.packet.flags, 1)
        for index in 0..<1000 { queue.append(packet(.video, size: 10_000), now: Double(index) / 30) }
        XCTAssertLessThan(queue.byteCount, 512_000)
    }
}
