import AppKit

// Approved Beam sender artwork, with separately hinted 16/32px optical sources.
guard CommandLine.arguments.count == 2 else { fatalError("Pass iconset directory") }
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let source = root.appendingPathComponent("assets/beam/macos-icon/icon-\(pixels).png")
        let suffix = scale == 2 ? "@2x" : ""
        let target = destination.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        let data = try Data(contentsOf: source)
        guard NSImage(data: data) != nil else { fatalError("Missing or invalid approved Beam icon: \(source.path)") }
        try data.write(to: target)
    }
}
