import Foundation

/// Local-network capacity is not decoder capacity. React to sustained receiver
/// drops only while the sender is producing motion, with a startup grace period.
public struct PlaybackCapacity {
    public private(set) var maximumFPS: Int
    public private(set) var scale = 1.0
    private var sample: (time: Double, frames: Int, drops: Int)?
    private var firstPresentation: Double?
    private var lastChange = -Double.infinity
    private let requestedMaximumFPS: Int
    private let preservesDetail: Bool
    private var healthySeconds = 0.0
    private var triedHighRate = false
    public init(maximumFPS: Int, preservesDetail: Bool = false) {
        requestedMaximumFPS = maximumFPS; self.maximumFPS = min(30, maximumFPS); self.preservesDetail = preservesDetail
    }
    public mutating func observe(frames: Int, drops: Int, inputFPS: Double, targetFPS: Int, paused: Bool, now: Double) -> Bool {
        guard let old = sample else { sample = (now, frames, drops); if frames > 0 { firstPresentation = now }; return false }
        let elapsed = now - old.time
        guard elapsed >= 1 else { return false }
        sample = (now, frames, drops)
        if frames > 0 && firstPresentation == nil { firstPresentation = now }
        guard !paused, frames >= old.frames, drops >= old.drops, elapsed < 3,
              let firstPresentation, now - firstPresentation >= 1,
              inputFPS >= Double(targetFPS) * 0.75 else { return false }
        let presentedFPS = Double(frames - old.frames) / elapsed
        let droppedFPS = Double(drops - old.drops) / elapsed
        if !triedHighRate && requestedMaximumFPS > 30 && targetFPS == 30 &&
            inputFPS >= Double(requestedMaximumFPS) * 0.75 && presentedFPS >= 25.5 && droppedFPS <= 4.5 {
            healthySeconds += elapsed
            if healthySeconds >= 5 {
                triedHighRate = true; maximumFPS = requestedMaximumFPS; lastChange = now
                return true
            }
        }
        guard presentedFPS < Double(targetFPS) * 0.8, droppedFPS >= Double(targetFPS) * 0.1 else { return false }
        healthySeconds = 0
        if targetFPS > 30 { maximumFPS = 30 }
        else if now - lastChange < 3 { return false }
        else if preservesDetail && maximumFPS > 24 { maximumFPS = 24 }
        else if preservesDetail && maximumFPS > 15 { maximumFPS = 15 }
        else if preservesDetail { return false }
        else if scale > 0.68 { scale = 2.0 / 3 }
        else if scale > 0.51 { scale = 0.5 }
        else { return false }
        lastChange = now
        return true
    }
}
