import SwiftUI
import Foundation
import Darwin

enum PulsePaths {
    static var data: URL {
        let realHome = String(cString: getpwuid(getuid())!.pointee.pw_dir)
        return URL(fileURLWithPath: realHome).appendingPathComponent("Library/Application Support/CodexPulse", isDirectory: true)
    }
}

struct QuotaPoint: Codable { let at: Double; let remaining: Double }
struct QuotaWindow: Codable, Identifiable {
    let id: String; let bucket: String; let name: String; let label: String
    let used: Double; let remaining: Double; let reset: Double?
    let burnRate: Double?; let hoursLeft: Double?; let history: [QuotaPoint]
}
struct PulseTask: Codable, Identifiable {
    let id: String; let title: String; let status: String; let at: Double
    var label: String { ["active":"运行中", "completed":"轮次结束", "interrupted":"已中断", "failed":"失败", "unknown":"待确认"][status] ?? "待确认" }
    var color: Color { status == "active" ? .cyan : status == "completed" ? .mint : status == "failed" ? .red : .secondary }
}
struct PulseEvent: Codable { let kind: String; let at: Double; let message: String }
struct KeyboardState: Codable { let status: String; let message: String }
struct PulseSnapshot: Codable {
    var generatedAt: Double; var quotaAt: Double; var windows: [QuotaWindow]; var tasks: [PulseTask]
    var events: [PulseEvent]; var quotaError: String?; var taskError: String?; var resetCredits: Int?
    var keyboard: KeyboardState
    static let empty = PulseSnapshot(generatedAt: 0, quotaAt: 0, windows: [], tasks: [], events: [], quotaError: "请先打开 Codex Pulse 启动监控", taskError: nil, resetCredits: nil, keyboard: KeyboardState(status: "off", message: "灯光关闭"))
    static func read() -> PulseSnapshot {
        guard let data = try? Data(contentsOf: PulsePaths.data.appendingPathComponent("snapshot.json")),
              let value = try? JSONDecoder().decode(PulseSnapshot.self, from: data) else { return .empty }
        return value
    }
    var mainWindows: [QuotaWindow] { windows.filter { $0.bucket == "codex" } }
    var primary: QuotaWindow? { mainWindows.min { $0.remaining < $1.remaining } }
    var stale: Bool { Date().timeIntervalSince1970 - quotaAt > 180 || Date().timeIntervalSince1970 - generatedAt > 30 || quotaError != nil }
    var activeCount: Int { tasks.filter { $0.status == "active" }.count }
    var completedToday: Int { tasks.filter { $0.status == "completed" && Calendar.current.isDateInToday(Date(timeIntervalSince1970: $0.at)) }.count }
}

let pulseMint = Color(red: 0.31, green: 0.94, blue: 0.73)

struct QuotaRing: View {
    let remaining: Double?
    let stale: Bool
    var size: CGFloat = 88
    var tint: Color { stale ? .gray : (remaining ?? 100) <= 10 ? .red : (remaining ?? 100) <= 25 ? .orange : pulseMint }
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.09), lineWidth: 7)
            Circle().trim(from: 0, to: min(1,max(0,(remaining ?? 0)/100)))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(remaining.map { String(format: "%.0f", $0) } ?? "—").font(.system(size: size*0.32, weight: .semibold, design: .rounded))
                Text("% 剩余").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(width: size, height: size)
    }
}

// Keep small changes visible without magnifying sub-percentage noise.
struct QuotaTrendScale {
    let lower: Double
    let upper: Double
    init(points: [QuotaPoint]) {
        let values = points.map { min(100, max(0, $0.remaining)) }
        guard let low = values.min(), let high = values.max() else {
            lower = 0; upper = 100; return
        }
        let padding = max(1, (high - low) * 0.15)
        let span = min(100, max(5, ceil(high + padding) - floor(low - padding)))
        lower = max(0, min(floor((low + high - span) / 2), 100 - span))
        upper = lower + span
    }
    func fraction(_ value: Double) -> Double {
        min(1, max(0, (value - lower) / (upper - lower)))
    }
}

struct Sparkline: View {
    let points: [QuotaPoint]
    var body: some View {
        let scale = QuotaTrendScale(points: points)
        HStack(spacing: 6) {
            if points.count >= 2, let first = points.first, let last = points.last {
                VStack {
                    Text(String(format: "%.0f%%", scale.upper))
                    Spacer(minLength: 0)
                    Text(String(format: "%.0f%%", scale.lower))
                }.font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
                GeometryReader { geo in
                    Path { path in
                        for (i, point) in points.enumerated() {
                            let x = (point.at-first.at)/max(1,last.at-first.at)*geo.size.width
                            let y = 2 + (1-scale.fraction(point.remaining))*max(0,geo.size.height-4)
                            if i == 0 { path.move(to: CGPoint(x:x,y:y)) } else { path.addLine(to:CGPoint(x:x,y:y)) }
                        }
                    }.stroke(pulseMint.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            } else {
                Text("开始记录额度趋势").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct PulseCard: View {
    let snapshot: PulseSnapshot
    var compact = false
    var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path").foregroundStyle(pulseMint)
                Text(compact ? "CODEX" : "CODEX PULSE").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.5).lineLimit(1)
                Spacer(minLength: 0)
                Circle().fill(snapshot.stale ? .orange : pulseMint).frame(width: 6,height: 6)
            }
            if compact {
                HStack {
                    QuotaRing(remaining: snapshot.primary?.remaining, stale: snapshot.stale, size: 70)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(snapshot.primary?.label ?? "额度").font(.caption)
                        Text("\(snapshot.activeCount) 运行").font(.system(size: 11)).foregroundStyle(.cyan)
                        Text(snapshot.stale ? "数据待更新" : "最近采样").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 20) {
                    QuotaRing(remaining: snapshot.primary?.remaining, stale: snapshot.stale, size: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(snapshot.primary.map { "\($0.name) · \($0.label)" } ?? "等待额度数据").font(.system(size: 13, weight: .medium))
                        if let rate = snapshot.primary?.burnRate {
                            Text(String(format: "%.1f 百分点 / 小时", rate)).font(.system(size: 12, design: .monospaced)).foregroundStyle(pulseMint)
                        } else { Text("消耗速度 · 积累样本中").font(.system(size: 11)).foregroundStyle(.secondary) }
                        if let reset = snapshot.primary?.reset {
                            HStack(spacing: 4) { Text("重置"); Text(Date(timeIntervalSince1970: reset), style: .relative) }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            Label("\(snapshot.activeCount) 运行", systemImage: "circle.dotted").foregroundStyle(.cyan)
                            Label("\(snapshot.completedToday) 今日结束", systemImage: "checkmark.circle").foregroundStyle(pulseMint)
                        }.font(.system(size: 10))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if expanded {
                Sparkline(points: snapshot.primary?.history ?? []).frame(height: 34)
                HStack {
                    Text("近一小时 · 自动缩放")
                    Spacer(minLength: 4)
                    if let first = snapshot.primary?.history.first, let last = snapshot.primary?.history.last {
                        Text(String(format: "%.0f%% → %.0f%%", first.remaining, last.remaining)).monospacedDigit()
                    }
                }.font(.system(size: 9)).foregroundStyle(.secondary)
                Divider().overlay(.white.opacity(0.06))
                ForEach(Array(snapshot.tasks.prefix(3))) { task in
                    HStack(spacing: 7) {
                        Circle().fill(task.color).frame(width: 5,height: 5)
                        Text(task.title).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(task.label).font(.system(size: 10)).foregroundStyle(task.color)
                    }
                }
                if let event = snapshot.events.last {
                    Text((event.kind == "reset" ? "↻ " : "• ") + event.message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 3) {
                Text(snapshot.stale ? "待更新" : "更新于")
                if snapshot.quotaAt > 0 { Text(Date(timeIntervalSince1970: snapshot.quotaAt), style: .time) }
                Spacer(minLength: 3)
                if !compact { Text("本机会话") }
            }.font(.system(size: 9)).foregroundStyle(snapshot.stale ? .orange : .secondary)
        }.foregroundStyle(.white)
    }
}
