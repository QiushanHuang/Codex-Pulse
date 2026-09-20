import AppKit

@main
struct MenuBarTests {
    static func main() throws {
        precondition(MenuBarPreferences().style == .waveform)
        precondition(MenuBarIconStyle.allCases.map(\.rawValue) == ["waveform", "waveformQuota"],
                     "The quota option must be waveform with a lower arc, not a battery")
        precondition(MenuBarPreferences(["style": "battery"]).style.rawValue == "waveformQuota",
                     "Existing quota-icon selection must migrate to the new waveform design")
        for style in MenuBarIconStyle.allCases {
            let value = MenuBarPreferences(["style": style.rawValue])
            precondition(MenuBarPreferences(value.dictionary) == value)
        }
        precondition(MenuBarPreferences(["style": "future-style"]).style == .waveform)
        for (remaining, fraction) in [(0.0, 0.0), (1, 0.01), (25, 0.25),
                                           (25.1, 0.251), (50, 0.5), (75, 0.75),
                                           (100, 1), (-10, 0), (150, 1)] {
            let state = MenuBarQuota(remaining: remaining, stale: false)
            precondition(state.fraction == fraction)
        }
        for remaining: Double? in [nil, .nan, .infinity] {
            precondition(MenuBarQuota(remaining: remaining, stale: false).fraction == nil)
        }
        precondition(MenuBarQuota(remaining: 70, stale: true).fraction == nil)
        precondition(MenuBarQuota(remaining: 0, stale: false).summary.contains("0%"))
        precondition(MenuBarQuota(remaining: 70, stale: true).summary.contains("待更新"))
        // The waveform stays fixed while only the lower arc gains ink as quota rises.
        var upperInk: Double?
        var previousLowerInk = -1.0
        for value in [0.0, 25, 50, 75, 100] {
            let icon = MenuBarIcon.image(style: .waveformQuota, quota: MenuBarQuota(remaining: value, stale: false))
            let pixels = NSBitmapImageRep(data: icon.tiffRepresentation!)!
            var upper = 0.0, lower = 0.0
            for y in 0..<pixels.pixelsHigh {
                for x in 0..<pixels.pixelsWide {
                    let alpha = Double(pixels.colorAt(x: x, y: y)!.alphaComponent)
                    if y < pixels.pixelsHigh / 3 { upper += alpha }
                    if y >= pixels.pixelsHigh / 2 { lower += alpha }
                }
            }
            precondition(upper > 0)
            if let upperInk { precondition(abs(upper - upperInk) < 0.001) }
            upperInk = upper
            precondition(lower > previousLowerInk, "More remaining quota must visibly fill more of the lower arc")
            previousLowerInk = lower
        }
        // Render real AppKit images at menu-bar size for inspection.
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for style in MenuBarIconStyle.allCases {
            for remaining: Double? in [0, 1, 25, 50, 75, 100, nil] {
                let state = MenuBarQuota(remaining: remaining, stale: false)
                let image = MenuBarIcon.image(style: style, quota: state)
                precondition(image.isTemplate && image.size.height == 18)
                let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                try rep.representation(using: .png, properties: [:])!.write(to:
                    directory.appendingPathComponent("\(style.rawValue)-\(remaining.map { String(Int($0)) } ?? "unknown").png"))
            }
        }
        let sheet = NSImage(size: NSSize(width: 600, height: 100), flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 600, height: 100).fill()
            for (index, value) in ([0, 25, 50, 75, 100, nil] as [Double?]).enumerated() {
                let image = MenuBarIcon.image(style: MenuBarPreferences(["style": "battery"]).style, quota: MenuBarQuota(remaining: value, stale: false))
                image.draw(in: NSRect(x: index * 100 + 11, y: 32, width: 78, height: 54))
                let label = value.map { "\(Int($0))%" } ?? "unknown"
                NSAttributedString(string: label, attributes: [.foregroundColor: NSColor.black])
                    .draw(at: NSPoint(x: index * 100 + 30, y: 10))
            }
            return true
        }
        let sheetRep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try sheetRep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("waveform-quota-sheet.png"))
        print("Menu bar preferences, quota boundaries, unknown state and rendering passed")
    }
}
