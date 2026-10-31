import XCTest
@testable import MirayaCore

final class SharingControlsTests: XCTestCase {
    func testMissingAndStaleMeasurementsCannotReportAHealthyConnection() {
        XCTAssertNotNil(StreamHealth.sampleStatus(senderAge: nil, receiverAge: 0))
        XCTAssertNotNil(StreamHealth.sampleStatus(senderAge: 0, receiverAge: nil))
        XCTAssertTrue(StreamHealth.sampleStatus(senderAge: 0, receiverAge: 4)!.contains("TV measurements"))
        XCTAssertTrue(StreamHealth.sampleStatus(senderAge: 4, receiverAge: 0)!.contains("Mac measurements"))
        XCTAssertTrue(StreamHealth.sampleStatus(senderAge: 4, receiverAge: 4)!.contains("out of date"))
        XCTAssertNil(StreamHealth.sampleStatus(senderAge: 1, receiverAge: 0.25))
    }
    func testAudioRoutesMatchTheirNames() {
        XCTAssertFalse(AudioDestination.mac.sendsToTV); XCTAssertFalse(AudioDestination.mac.mutesMac)
        XCTAssertTrue(AudioDestination.tv.sendsToTV); XCTAssertTrue(AudioDestination.tv.mutesMac)
        XCTAssertTrue(AudioDestination.both.sendsToTV); XCTAssertFalse(AudioDestination.both.mutesMac)
    }
    func testNetworkAndEncoderLimitsAreNotConfused() {
        func diagnose(_ reason: String = "none", _ rtt: Double = 3, _ loss: Double = 0, _ scale: Double = 1) -> String {
            StreamHealth.diagnosis(encoderReason: reason, receiverScale: scale, decoderFPS: 60, frameCap: 60, requestedFPS: 60, rttMs: rtt, lossPercent: loss)
        }
        XCTAssertTrue(diagnose("cpu").contains("CPU"))
        XCTAssertTrue(diagnose("bandwidth").contains("estimate"))
        XCTAssertTrue(diagnose("none", 3, 4).contains("packet loss"))
        XCTAssertTrue(diagnose("none", 180).contains("round-trip"))
        XCTAssertTrue(diagnose("none", 3, 0, 0.66).contains("picture size"))
        XCTAssertTrue(diagnose().contains("Static"))
    }
    func testFirstPictureIsAnExplicitStartupMilestone() {
        XCTAssertTrue(ConnectionStep.contactingTV.detail.contains("received"))
        XCTAssertTrue(ConnectionStep.waitingForPicture.detail.contains("presents a frame"))
        XCTAssertNotEqual(ConnectionStep.startingCapture, .waitingForPicture)
    }
    func testReceiverDropsAreDistinguishedFromStaticContent() {
        let overloaded = StreamHealth.diagnosis(encoderReason: "none", receiverScale: 1, decoderFPS: 60, frameCap: 60, requestedFPS: 60, rttMs: 4, lossPercent: 0, inputFPS: 60, playbackFPS: 20, droppedFPS: 25)
        XCTAssertTrue(overloaded.contains("TV is presenting fewer frames"))
        let staticScreen = StreamHealth.diagnosis(encoderReason: "none", receiverScale: 1, decoderFPS: 60, frameCap: 60, requestedFPS: 60, rttMs: 4, lossPercent: 0, inputFPS: 2, playbackFPS: 2, droppedFPS: 0)
        XCTAssertTrue(staticScreen.contains("Static"))
    }
}
