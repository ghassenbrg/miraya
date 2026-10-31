// PROPOSAL ONLY — NOT IMPLEMENTED
// Converts system typography into portable paths; ships no font binary.
import AppKit
import CoreText
import Foundation
let font = CTFontCreateWithName(NSFont.systemFont(ofSize: 120, weight: .semibold).fontName as CFString, 120, nil)
var position: CGFloat = 0
var output = ""
func n(_ x: CGFloat) -> String { String(format: "%.3f", Double(x)) }
let text = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Miraya"
for character in text.utf16 {
    var value = character, glyph: CGGlyph = 0
    CTFontGetGlyphsForCharacters(font, &value, &glyph, 1)
    if let path = CTFontCreatePathForGlyph(font, glyph, nil) {
        let offset = position
        func point(_ p: CGPoint) -> String { "\(n(p.x + offset)) \(n(116 - p.y))" }
        path.applyWithBlock { pointer in
            let e = pointer.pointee
            switch e.type {
            case .moveToPoint: output += "M\(point(e.points[0]))"
            case .addLineToPoint: output += "L\(point(e.points[0]))"
            case .addQuadCurveToPoint: output += "Q\(point(e.points[0])) \(point(e.points[1]))"
            case .addCurveToPoint: output += "C\(point(e.points[0])) \(point(e.points[1])) \(point(e.points[2]))"
            case .closeSubpath: output += "Z"
            @unknown default: break
            }
        }
    }
    var size = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &size, 1)
    position += size.width - 2.2
}
let data = try JSONSerialization.data(withJSONObject: ["status":"PROPOSAL ONLY — NOT IMPLEMENTED", "word":text, "path":output, "width":Double(position + 4), "height":150], options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
