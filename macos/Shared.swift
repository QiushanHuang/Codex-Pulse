import SwiftUI
import Foundation
import Darwin
import AppKit

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
    var tokensUsed: Int? = nil
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var cachedInputTokens: Int? = nil
    var comparableTokens:Int? {tokensUsed.flatMap{$0>=0 ? $0:nil}}
    var tokenLabel: String { comparableTokens.map { PulseUsageFormat.compact(Double($0)) + " tokens" } ?? "— tokens" }
    var usageSummary: String { tokenLabel + " · Credit 未提供" }
    var label: String { ["active":"运行中", "completed":"轮次结束", "interrupted":"已中断", "failed":"失败", "unknown":"待确认"][status] ?? "待确认" }
    var color: Color { status == "active" ? .cyan : status == "completed" ? .mint : status == "failed" ? .red : .secondary }
}
enum PulseUsageFormat {
    static func compact(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format:"%.2fM",value / 1_000_000) }
        if value >= 1_000 { return String(format:"%.1fK",value / 1_000) }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier:"en_US")))
    }
}
struct PulseCredits: Codable {
    let balance: Double?
    let unlimited: Bool
    func display(fresh: Bool, compact: Bool = false) -> String {
        guard fresh else { return "—" }
        if unlimited { return "∞" }
        guard let balance, balance.isFinite else { return "—" }
        return compact ? PulseUsageFormat.compact(balance) : balance.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier:"en_US")))
    }
}
struct ResetVoucher:Codable,Identifiable {let id:String;let expiresAt:Double?;let grantedAt:Double?}
struct QuotaResetResult:Codable {
    let requestID:String
    let accountKey:String
    let state:String
    let outcome:String?
    let message:String
    let at:Double
    var uncertain:Bool {state == "pending" || state == "unknown"}
    var succeeded:Bool {state == "completed" && (outcome == "reset" || outcome == "alreadyRedeemed")}
    func pendingID(for key:String?)->String? {
        guard uncertain,key==accountKey,UUID(uuidString:requestID) != nil else{return nil}
        return requestID.lowercased()
    }
}
enum QuotaResetPolicy {
    static func validAccount(_ key:String?)->Bool {key?.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil}
    static func canStart(accountKey:String?,fresh:Bool,count:Int?,busy:Bool,result:QuotaResetResult?)->Bool {
        guard !busy,validAccount(accountKey) else{return false}
        return result?.pendingID(for:accountKey) != nil || (fresh && (count ?? 0)>0)
    }
}
struct PulseEvent: Codable { let kind: String; let at: Double; let message: String }
struct KeyboardState: Codable { let status: String; let message: String }
struct PulseSnapshot: Codable {
    var generatedAt: Double; var quotaAt: Double; var windows: [QuotaWindow]; var tasks: [PulseTask]
    var events: [PulseEvent]; var quotaError: String?; var taskError: String?; var resetCredits: Int?
    var credits: PulseCredits? = nil
    var accountKey:String? = nil
    var resetVouchers:[ResetVoucher]? = nil
    var usage: AccountUsage? = nil
    var usageAt: Double? = nil
    var usageError: String? = nil
    var usageStale:Bool {usageError != nil || Date().timeIntervalSince1970-(usageAt ?? 0)>660 || Date().timeIntervalSince1970-generatedAt>30}
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

let pulseMint = Color(nsColor:NSColor(name:nil) { appearance in
    appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ?
        NSColor(srgbRed:0.31,green:0.94,blue:0.73,alpha:1):NSColor(srgbRed:0.015,green:0.43,blue:0.32,alpha:1)
})

let pulseCredit = Color(nsColor:NSColor(name:nil) { appearance in
    appearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua ?
        NSColor(srgbRed:0.77,green:0.65,blue:1,alpha:1):NSColor(srgbRed:0.43,green:0.23,blue:0.76,alpha:1)
})

// WidgetKit composites its own material over this source gradient.
struct PulseWidgetBackground: View {
    var body: some View {
        LinearGradient(colors:[Color(red:0.055,green:0.11,blue:0.14),Color(red:0.04,green:0.065,blue:0.09)],
                       startPoint:.topLeading,endPoint:.bottomTrailing)
    }
}

struct PulseWindowBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if scheme == .dark {
                // Match the visible WidgetKit surface, not its uncomposited source.
                // Sampled from the reference widget: upper ~42/53/60, lower ~23/34/39.
                LinearGradient(colors:[
                    Color(red:46.0/255,green:58.0/255,blue:65.0/255),
                    Color(red:31.0/255,green:41.0/255,blue:48.0/255),
                    Color(red:22.0/255,green:32.0/255,blue:37.0/255)
                ],startPoint:.top,endPoint:.bottom)
                .overlay(LinearGradient(colors:[.white.opacity(0.008),.black.opacity(0.025)],
                                        startPoint:.leading,endPoint:.trailing))
            }
            else {
                LinearGradient(colors:[Color(red:0.95,green:0.97,blue:0.97),Color(red:0.89,green:0.93,blue:0.94)],
                               startPoint:.topLeading,endPoint:.bottomTrailing)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

enum RingPalette {
    static func color(_ hex:String?,fallback:Color)->Color {
        guard let text=DesktopPalette.normalized(hex),let rgb=UInt32(text.dropFirst(),radix:16) else {return fallback}
        return Color(.sRGB,red:Double((rgb>>16)&255)/255,green:Double((rgb>>8)&255)/255,blue:Double(rgb&255)/255,opacity:1)
    }
    static func hex(_ color:Color)->String {
        let rgb=NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
    }
}
private struct RingOuterColorKey:EnvironmentKey {static let defaultValue=pulseMint}
private struct RingInnerColorKey:EnvironmentKey {static let defaultValue=pulseCredit}
private struct GlassTransparencyKey:EnvironmentKey {static let defaultValue=0.98}
private struct GlassMaterialKey:EnvironmentKey {static let defaultValue:GlassMaterial = .clear}
extension EnvironmentValues {
    var ringOuterColor:Color {get {self[RingOuterColorKey.self]} set {self[RingOuterColorKey.self]=newValue}}
    var ringInnerColor:Color {get {self[RingInnerColorKey.self]} set {self[RingInnerColorKey.self]=newValue}}
    var glassMaterial:GlassMaterial {get {self[GlassMaterialKey.self]} set {self[GlassMaterialKey.self]=newValue}}
    var glassTransparency:Double {get {self[GlassTransparencyKey.self]} set {self[GlassTransparencyKey.self]=newValue}}
}
extension View {
    func desktopAppearance(_ preferences:DesktopPreferences)->some View {
        self.environment(\.ringCenterContent,preferences.ringCenter)
            .environment(\.ringOuterColor,RingPalette.color(preferences.outerRingColor,fallback:pulseMint))
            .environment(\.ringInnerColor,RingPalette.color(preferences.innerRingColor,fallback:pulseCredit))
            .environment(\.glassTransparency,preferences.glassTransparency)
            .environment(\.glassMaterial,preferences.glassMaterial)
    }
}

private struct RingCenterEnvironmentKey:EnvironmentKey {static let defaultValue:RingCenterContent = .credit}
extension EnvironmentValues {
    var ringCenterContent:RingCenterContent {
        get {self[RingCenterEnvironmentKey.self]}
        set {self[RingCenterEnvironmentKey.self]=newValue}
    }
}

struct QuotaRing: View {
    @Environment(\.ringCenterContent) private var center
    @Environment(\.ringOuterColor) private var outerColor
    @Environment(\.ringInnerColor) private var innerColor
    let remaining: Double?
    let stale: Bool
    var size: CGFloat = 88
    var credits: PulseCredits? = nil
    var resetCredits:Int? = nil
    private var valid: Double? { guard !stale, let remaining, remaining.isFinite else { return nil }; return max(0,min(100,remaining)) }
    private var balance: String { credits?.display(fresh:!stale,compact:true) ?? "—" }
    private var percent:String {valid.map{String(format:"%.0f",$0)} ?? "—"}
    private var centerColor:Color {center == .percentage ? outerColor:innerColor}
    private var centerText:String {
        switch center {
        case .credit:return balance
        case .percentage:return percent
        case .resetCredits:return !stale ? resetCredits.flatMap{$0>=0 ? String($0):nil} ?? "—":"—"
        }
    }
    private var centerUnit:String {center == .credit ? "credit":center == .percentage ? "% 剩余":"次重置"}
    var body: some View {
        let width=max(2,size*0.055)
        ZStack {
            Circle().stroke(Color.primary.opacity(0.09),style:StrokeStyle(lineWidth:width,dash:valid == nil ? [2,3]:[]))
            if let valid {
                Circle().trim(from:0,to:valid/100).stroke(valid<=10 ? .red:outerColor,style:StrokeStyle(lineWidth:width,lineCap:.round)).rotationEffect(.degrees(-90))
            }
            // No credit capacity is supplied. A dashed inner key identifies the
            // balance; it deliberately does not encode a made-up percentage.
            Circle().stroke(balance == "—" ? Color.secondary.opacity(0.25):innerColor.opacity(0.55),style:StrokeStyle(lineWidth:max(1.3,width*0.55),dash:[2,3]))
                .padding(size*0.105)
            VStack(spacing:size*0.015) {
                Text(centerText).font(.system(size:size*(center == .credit ? 0.205:0.27),weight:.semibold,design:.rounded)).monospacedDigit()
                    .foregroundStyle(stale ? Color.secondary:centerColor).lineLimit(1).minimumScaleFactor(0.5)
                if size>=60 {Text(centerUnit).font(.system(size:max(8,size*0.095))).foregroundStyle(centerColor)}
                if size>=52 {Text(center == .percentage ? balance+" cr":percent+"%")
                    .font(.system(size:max(8,size*0.115),weight:.medium)).foregroundStyle(stale ? Color.secondary:(center == .credit ? outerColor:innerColor))}
            }.frame(width:size*0.56)
        }.padding(width/2).frame(width:size,height:size)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("剩余额度 \(valid.map{String(format:"%.0f%%",$0)} ?? "待更新")，Credit 余额 \(credits?.display(fresh:!stale) ?? "未提供")，可用重置次数 \(!stale ? resetCredits.map{String($0)} ?? "未提供":"待更新") 次")
            .help("外环表示套餐剩余百分比；环内可切换显示。Credit 余额和可用重置次数独立，内环标识不表示比例。")
    }
}

struct CreditBalanceLine: View {
    let snapshot: PulseSnapshot
    var running = true
    var body: some View {
        VStack(spacing:5) {
            HStack {
                Label("Credit 余额",systemImage:"circle.dotted")
                Spacer(minLength:4)
                Text(snapshot.credits?.display(fresh:!snapshot.stale && running) ?? "未提供").monospacedDigit()
            }
            HStack {
                Label("可用重置次数",systemImage:"arrow.counterclockwise")
                Spacer(minLength:4)
                Text(!snapshot.stale && running ? snapshot.resetCredits.map{"\($0) 次"} ?? "未提供":"待更新").monospacedDigit()
            }
        }.font(.system(size:11,weight:.medium)).foregroundStyle(pulseCredit)
            .help("Credit 按用量扣减；重置券用于恢复符合条件的套餐窗口。两项独立，使用重置券前需确认。")
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
    var headerControls: AnyView? = nil
    var adaptiveForeground = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                HStack(spacing:7) {
                    Image(systemName:"waveform.path").foregroundStyle(pulseMint)
                    Text(compact ? "CODEX":"CODEX PULSE").font(.system(size:11,weight:.bold,design:.rounded)).tracking(1.5).lineLimit(1)
                }.frame(maxWidth:.infinity,minHeight:18,alignment:.leading)

                if let headerControls {headerControls}
                Circle().fill(snapshot.stale ? .orange : pulseMint).frame(width: 6,height: 6)
            }
            if compact {
                HStack {
                    QuotaRing(remaining: snapshot.primary?.remaining, stale: snapshot.stale, size: 70, credits:snapshot.credits,resetCredits:snapshot.resetCredits)
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(snapshot.primary?.label ?? "额度").font(.caption)
                        Text("\(snapshot.activeCount) 运行").font(.system(size: 11)).foregroundStyle(.cyan)
                        Text(snapshot.stale ? "数据待更新" : "最近采样").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 20) {
                    QuotaRing(remaining: snapshot.primary?.remaining, stale: snapshot.stale, size: 84, credits:snapshot.credits,resetCredits:snapshot.resetCredits)
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
            CreditBalanceLine(snapshot:snapshot)
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
                        VStack(alignment:.leading,spacing:3) {
                            Text(task.title).font(.system(size:11)).lineLimit(1)
                            Text(task.usageSummary).font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
                        }
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
        }.foregroundStyle(adaptiveForeground ? Color.primary : .white)
    }
}
