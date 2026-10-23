import AppKit
import SwiftUI

@main struct RingTextTests {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("ring-text")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [60.0, 52, 67, 96, 160] {
            let ring = QuotaRing(remaining: 98, stale: false, size: size,
                                 credits: PulseCredits(balance: 62500, unlimited: false))
            let view = ring
                .environment(\.ringCenterContent, .percentage)
                .environment(\.ringInnerColor, Color(red: 1, green: 0, blue: 1))
                .environment(\.ringOuterColor, .green)
                .environment(\.colorScheme, .dark)
                .background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
            try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("ring-\(Int(size)).png"))
            // Count the credit glyph rows inside the inner ring, excluding its
            // dashed stroke. The complete balance and unit must share one line.
            let center = Double(rep.pixelsWide) / 2
            var rows = [Int]()
            for y in 0..<rep.pixelsHigh {
                var pixels = 0
                for x in 0..<rep.pixelsWide {
                    let radius = hypot(Double(x) - center, Double(y) - center) / Double(rep.pixelsWide)
                    guard radius < 0.34 || (radius > 0.395 && radius < 0.46) else { continue }
                    let color = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    if color.redComponent > 0.4 && color.blueComponent > 0.4 && color.greenComponent < 0.2 { pixels += 1 }
                }
                if pixels >= 2 { rows.append(y) }
            }
            let lines = rows.enumerated().filter { index, row in index == 0 || row - rows[index - 1] > 3 }.count
            guard lines == 1 else {
                print("FAIL: \(Int(size))-point ring wraps Credit into \(lines) visible lines; expected one complete line")
                exit(1)
            }
            let preview = ImageRenderer(content: ring.environment(\.ringCenterContent, .percentage)
                .environment(\.colorScheme, .dark).background(Color.black))
            preview.scale = 3
            let display = NSBitmapImageRep(cgImage: preview.cgImage!)
            try display.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("ring-\(Int(size))-display.png"))
        }
        print("PASS: Credit stays on one line at 52, 60, 67, 96 and 160 points")
    }
}
