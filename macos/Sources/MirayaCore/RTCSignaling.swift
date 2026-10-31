import Foundation

/// All SDP and candidates travel over the already authenticated TLS session.
/// The media session ID rejects late signals from a replaced peer connection.
public enum RTCSignaling {
    public static let transport = "webrtc-udp-v1"
    public static func validSession(_ value: String) -> Bool { UUID(uuidString: value) != nil }
    /// Respect the receiving decoder's H.264 level. Some older TVs only expose
    /// level 3.1; adapting the source prevents a valid negotiation from freezing
    /// on an oversized frame. Unknown levels use the conservative 720p30 bound.
    public static func h264ReceiveLimit(_ sdp: String) -> (width: Int, height: Int, fps: Int) {
        let lines = sdp.components(separatedBy: .newlines)
        let payloads = lines.filter { $0.hasPrefix("a=rtpmap:") && $0.lowercased().contains(" h264/90000") }
            .map { String($0.dropFirst(9).prefix(while: { $0 != " " })) }
        let levels = payloads.map { payload -> Int in
            guard let line = lines.first(where: { $0.hasPrefix("a=fmtp:\(payload) ") }),
                  let range = line.range(of: "profile-level-id=", options: .caseInsensitive) else { return 31 }
            let hex = line[range.upperBound...].prefix(6)
            guard hex.count == 6 else { return 31 }
            return Int(hex.suffix(2), radix: 16) ?? 31
        }
        let level = levels.min() ?? 31
        if level >= 42 { return (1920, 1080, 60) }
        if level >= 40 { return (1920, 1080, 30) }
        return (1280, 720, 30)
    }
    public static func validateSDP(_ sdp: String) throws {
        guard sdp.utf8.count <= 32_768, sdp.hasPrefix("v=0\r\n") || sdp.hasPrefix("v=0\n") else { throw WireError.invalidControl }
        let lines = sdp.components(separatedBy: .newlines)
        let media = lines.filter { $0.hasPrefix("m=") }
        let fingerprints = lines.filter { $0.hasPrefix("a=fingerprint:") }
        guard !media.isEmpty, media.count <= 2, media.allSatisfy({
            ($0.hasPrefix("m=video ") || $0.hasPrefix("m=audio ")) && $0.contains("UDP/TLS/RTP/SAVPF")
        }), media.filter({ $0.hasPrefix("m=video ") }).count == 1, media.filter({ $0.hasPrefix("m=audio ") }).count <= 1,
        !fingerprints.isEmpty, fingerprints.allSatisfy({ $0.range(of: "^a=fingerprint:sha-256 ([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$", options: .regularExpression) != nil }),
        lines.contains(where: { $0.hasPrefix("a=ice-ufrag:") }), lines.contains(where: { $0.hasPrefix("a=ice-pwd:") }) else { throw WireError.invalidControl }
        for line in lines where line.hasPrefix("a=candidate:") { try validateCandidate(String(line.dropFirst(2)), mid: nil, index: 0) }
    }
    public static func validateCandidate(_ sdp: String, mid: String?, index: Int) throws {
        let fields = sdp.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard sdp.utf8.count <= 4096, !sdp.utf8.contains(10), !sdp.utf8.contains(13), (0...1).contains(index),
              (mid?.utf8.count ?? 0) <= 64, mid?.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) != false,
              fields.count >= 8, fields[0].hasPrefix("candidate:"),
              fields[2].lowercased() == "udp", let port = UInt16(fields[5]), port > 0,
              fields[6] == "typ", fields[7] == "host" || fields[7] == "prflx" else { throw WireError.invalidControl }
    }
    /// Preserve negotiated Opus payload IDs; request stereo music/movie audio.
    public static func stereoOpus(_ sdp: String) -> String {
        let lines = sdp.components(separatedBy: "\r\n")
        let payloads = lines.compactMap { line -> String? in
            guard line.hasPrefix("a=rtpmap:"), line.lowercased().contains(" opus/48000/") else { return nil }
            return String(line.dropFirst(9).prefix(while: { $0 != " " }))
        }
        return lines.map { line in
            guard let payload = payloads.first(where: { line.hasPrefix("a=fmtp:\($0) ") }) else { return line }
            let prefix = "a=fmtp:\(payload) "
            var values = String(line.dropFirst(prefix.count)).split(separator: ";").map(String.init)
            values.removeAll { ["stereo", "sprop-stereo", "maxaveragebitrate", "usedtx"].contains(String($0.split(separator: "=").first ?? "")) }
            values += ["stereo=1", "sprop-stereo=1", "maxaveragebitrate=192000", "usedtx=0"]
            return prefix + values.joined(separator: ";")
        }.joined(separator: "\r\n")
    }
}
