import SwiftUI
import AppKit

@main
struct TrendTests {
    @MainActor static func main() throws {
        let points = [QuotaPoint(at: 0, remaining: 37), QuotaPoint(at: 3600, remaining: 32)]
        let renderer = ImageRenderer(content: Sparkline(points: points).frame(width: 300, height: 34).foregroundStyle(.white).preferredColorScheme(.dark).background(Color.black))
        renderer.scale = 2
        let rep = NSBitmapImageRep(data: renderer.nsImage!.tiffRepresentation!)!
        var rows = Set<Int>()
        for y in 0..<rep.pixelsHigh {
            for x in 120..<480 {
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if c.alphaComponent > 0.3 && c.greenComponent > c.redComponent + 0.2 {
                    rows.insert(y)
                }
            }
        }
        let span = (rows.max() ?? 0) - (rows.min() ?? 0)
        guard span >= 20 else {
            print("FAIL: 37% → 32% is visually flat: vertical span \(span)/68 pixels")
            exit(1)
        }
        for values in [[32.0, 37], [50, 50], [0, 0], [100, 100], [0, 100], [99, 100], [0, 1]] {
            let samples = values.enumerated().map { QuotaPoint(at: Double($0.offset), remaining: $0.element) }
            let scale = QuotaTrendScale(points: samples)
            precondition(scale.lower >= 0 && scale.upper <= 100 && scale.upper - scale.lower >= 5)
            precondition(scale.lower <= values.min()! && scale.upper >= values.max()!)
            precondition(scale.fraction(values[0]).isFinite)
            if values[0] == values[1] {
                precondition(scale.fraction(values[0]) == scale.fraction(values[1]), "Constant quota must remain flat")
            }
        }
        let empty = QuotaTrendScale(points: [])
        precondition(empty.lower == 0 && empty.upper == 100)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("trend.png"))
        print("PASS: 5-point decline is visible (\(span)/68 pixels)")
    }
}
