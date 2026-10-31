public enum StreamHealth {
    public static func sampleStatus(senderAge: Double?, receiverAge: Double?) -> String? {
        guard let senderAge, let receiverAge else { return "Waiting for measurements from the Mac and TV." }
        if senderAge > 3 && receiverAge > 3 { return "Measurements are out of date. Waiting for fresh Mac and TV statistics." }
        if receiverAge > 3 { return "TV measurements are out of date. Network and playback diagnosis may be incomplete." }
        if senderAge > 3 { return "Mac measurements are out of date. Encoder and bandwidth diagnosis may be incomplete." }
        return nil
    }
    public static func diagnosis(encoderReason: String, receiverScale: Double, decoderFPS: Int, frameCap: Int, requestedFPS: Int, rttMs: Double, lossPercent: Double, inputFPS: Double = 0, playbackFPS: Double = 0, droppedFPS: Double = 0) -> String {
        if lossPercent > 2 { return "Video packet loss is elevated. Check Wi-Fi signal, interference and other traffic on both devices." }
        if rttMs > 100 { return "Network round-trip delay is elevated. Check the local network; this does not measure distance from the router." }
        if encoderReason == "cpu" { return "The Mac encoder reports a CPU limit. Try a lower frame rate and close heavy background apps." }
        if encoderReason == "bandwidth" { return "The encoder is adapting to its bandwidth estimate. The estimate is not a LAN speed test." }
        if !encoderReason.isEmpty && encoderReason != "none" { return "The encoder reports another adaptation limit. Compare actual picture size, frame rate and decoder limits below." }
        if inputFPS >= 15 && playbackFPS < min(inputFPS, Double(max(1, frameCap))) * 0.75 && droppedFPS >= 5 { return "The TV is presenting fewer frames while reporting drops. Try 30 fps or close other TV apps; these samples alone do not identify the cause." }
        if receiverScale < 0.99 { return "TV playback adaptation reduced picture size. Prefer picture detail, or lower the requested frame rate." }
        if decoderFPS > 0 && decoderFPS < requestedFPS { return "The negotiated TV decoder limit is below the selected maximum frame rate." }
        if frameCap > 0 && frameCap < requestedFPS { return "Playback currently uses a lower frame-rate cap to keep the TV responsive." }
        return "No network or encoder limit is currently reported. Static screens and lower-frame-rate video naturally produce fewer frames."
    }
}
