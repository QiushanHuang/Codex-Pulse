import AppKit

enum MenuBarIconStyle: String, CaseIterable {
    case waveform, waveformQuota
    var title: String {
        switch self {
        case .waveform: return "原始波形"
        case .waveformQuota: return "波形 + 额度半环"
        }
    }
}

struct MenuBarPreferences: Equatable {
    var style: MenuBarIconStyle
    init(_ values: [String: Any] = [:]) {
        let saved = values["style"] as? String ?? ""
        style = saved == "battery" ? .waveformQuota : MenuBarIconStyle(rawValue: saved) ?? .waveform
    }
    var dictionary: [String: Any] { ["style": style.rawValue] }
}

struct MenuBarQuota {
    let fraction: Double?
    init(remaining: Double?, stale: Bool) {
        if !stale, let remaining, remaining.isFinite {
            fraction = min(1, max(0, remaining / 100))
        } else { fraction = nil }
    }
    var summary: String {
        fraction.map { "Codex 剩余 \(Int(($0 * 100).rounded()))%" } ?? "额度待更新"
    }
}

enum MenuBarIcon {
    static func image(style: MenuBarIconStyle, quota: MenuBarQuota) -> NSImage {
        if style == .waveform {
            let image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Codex Pulse")!
            image.size = NSSize(width: 22, height: 18)
            image.isTemplate = true
            return image
        }
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            let waveform = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(paletteColors: [.black]))!
            waveform.draw(in: NSRect(x: 1, y: 6, width: 20, height: 12))

            // Lower semicircle: fill travels from the left, through the bottom, to the right.
            func arc(_ fraction: Double) -> NSBezierPath {
                let path = NSBezierPath()
                path.appendArc(withCenter: NSPoint(x: 11, y: 7), radius: 5.5,
                               startAngle: 180, endAngle: 180 + 180 * fraction)
                path.lineWidth = 1.3
                path.lineCapStyle = .round
                return path
            }
            let track = arc(1)
            if quota.fraction == nil {
                // Broken track distinguishes unknown data from a real, empty quota arc.
                track.setLineDash([1, 2.5], count: 2, phase: 0)
            }
            NSColor.black.withAlphaComponent(quota.fraction == nil ? 0.45 : 0.22).setStroke()
            track.stroke()
            if let fraction = quota.fraction, fraction > 0 {
                NSColor.black.setStroke()
                arc(fraction).stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
