import SwiftUI
import Foundation
import AppKit

enum PreviewAnimationPolicy {
    static func shouldAnimate(visible:Bool,healthy:Bool,frameCount:Int)->Bool {
        visible && healthy && frameCount > 1
    }
}

// SwiftUI views can remain mounted after their window closes or is occluded.
struct PreviewVisibility: NSViewRepresentable {
    var changed:(Bool)->Void
    func makeNSView(context:Context)->VisibilityView { let view=VisibilityView();view.changed=changed;return view }
    func updateNSView(_ view:VisibilityView,context:Context) { view.changed=changed }
    static func dismantleNSView(_ view:VisibilityView,coordinator:()) { view.stop() }
    final class VisibilityView:NSView {
        var changed:((Bool)->Void)?
        private var observers:[NSObjectProtocol]=[]
        private var last:Bool?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow();stopObservers()
            if let window {
                for name in [NSWindow.didChangeOcclusionStateNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,NSWindow.willCloseNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName:name,object:window,queue:.main){[weak self] note in
                        MainActor.assumeIsolated { self?.report(closing:note.name == NSWindow.willCloseNotification) }
                    })
                }
            }
            report()
        }
        private func report(closing:Bool=false) {
            let visible = !closing && window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true
            guard visible != last else{return};last=visible
            DispatchQueue.main.async {[weak self] in guard let self,self.last==visible else{return};self.changed?(visible)}
        }
        private func stopObservers(){for observer in observers {NotificationCenter.default.removeObserver(observer)};observers=[]}
        func stop(){stopObservers();changed?(false);changed=nil}
        deinit {for observer in observers {NotificationCenter.default.removeObserver(observer)}}
    }
}

enum RunningStyle: String, CaseIterable, Identifiable {
    case classic, wave, pulse, ripple, comet
    var id: String { rawValue }
    func title(_ count: Int) -> String {
        let names: [RunningStyle:[String]] = [
            .classic:["经典外圈","经典双区","等距上行","斜线平移"],
            .wave:["柔光环浪","上下交叠","错峰潮汐","四排柔浪"],
            .pulse:["环形心跳","双区呼应","三拍律动","四拍轮动"],
            .ripple:["中心涟漪","双心涟漪","斜向涟漪","水波横移"],
            .comet:["流星拖尾","双星环绕","三道流光","四道星轨"]]
        return names[self]![max(0,min(3,count-1))]
    }
    var detail: String {
        switch self {
        case .classic:return "保留原有分组、轨迹和间距。"
        case .wave:return "宽柔波峰带着缓急变化，明暗像潮汐一样起伏。"
        case .pulse:return "主拍与轻拍交替，各组按节奏依次呼应。"
        case .ripple:return "光从不同位置向外扩散，形成相互交叠的涟漪。"
        case .comet:return "亮点加速、减速穿行，留下渐渐消散的长拖尾。"
        }
    }
    static func defaultFor(_ count:Int)->RunningStyle { count==1 ? .comet:count>=4 ? .ripple:.wave }
}

struct LightingPreviewData: Decodable {
    let active: Bool
    let startedAt: Double
    let mode: String?
    let style: String?
    let taskCount: Int?
    let frameSeconds: Double?
    let keys: [String]?
    let frames: [[Int]]?
    let demo: Bool?
    let deviceKey:String?
    func isCurrent(for key:String?)->Bool {key != nil && deviceKey == key}
    func rgb(_ key:String,at time:Double)->(Double,Double,Double) {
        guard active,let keys,let index=keys.firstIndex(of:key),let frames,!frames.isEmpty,
              let duration=frameSeconds,duration>0 else { return (0,0,0) }
        let position=max(0,time-startedAt)/duration
        let i=Int(position.truncatingRemainder(dividingBy:Double(frames.count)))
        let j=(i+1)%frames.count
        guard index<frames[i].count,index<frames[j].count else { return (0,0,0) }
        let blend=frames.count==1 ? 0:position-floor(position)
        func channel(_ shift:Int)->Double {
            let a=Double((frames[i][index]>>shift)&255),b=Double((frames[j][index]>>shift)&255)
            return (a+(b-a)*blend)/255
        }
        return (channel(16),channel(8),channel(0))
    }
}

@MainActor
final class LightingDiagramStore: ObservableObject {
    @Published var plan: LightingPreviewData?
    @Published var healthy=false
    private var timer: Timer?
    private var planDate: Date?
    private var healthDate: Date?
    private var heartbeat=0.0
    private var connected=false
    private var lastLease=Date.distantPast
    func start() {
        guard timer==nil else { return };poll()
        timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in Task { @MainActor in self?.poll() } }
        timer?.tolerance=0.05
    }
    func stop() { timer?.invalidate();timer=nil;plan=nil;planDate=nil;healthy=false }
    func poll() {
        if Date().timeIntervalSince(lastLease)>1 {
            // A short lease survives multiple viewers and expires after hidden windows stop polling.
            let lease=PulsePaths.data.appendingPathComponent("preview-viewer.lease")
            if FileManager.default.fileExists(atPath:lease.path) {
                try? FileManager.default.setAttributes([.modificationDate:Date()],ofItemAtPath:lease.path)
            } else {try? Data().write(to:lease,options:.atomic)}
            lastLease=Date()
        }
        let path=PulsePaths.data.appendingPathComponent("lighting-preview.json")
        let modified=(try? FileManager.default.attributesOfItem(atPath:path.path)[.modificationDate]) as? Date
        if modified != planDate {
            planDate=modified
            plan=(try? Data(contentsOf:path)).flatMap { try? JSONDecoder().decode(LightingPreviewData.self,from:$0) }
        }
        let status=PulsePaths.data.appendingPathComponent("keyboard.json")
        let changed=(try? FileManager.default.attributesOfItem(atPath:status.path)[.modificationDate]) as? Date
        if changed != healthDate {
            healthDate=changed
            if let data=try? Data(contentsOf:status),let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
                heartbeat=value["at"] as? Double ?? 0;connected=value["status"] as? String=="connected"
            } else { connected=false }
        }
        let alive=connected && Date().timeIntervalSince1970-heartbeat<20 && plan?.active==true
        if healthy != alive { healthy=alive }
    }
}

struct AnimatedKeyboardDiagram: View {
    @StateObject private var store=LightingDiagramStore()
    @State private var visible=false
    var expectedDeviceKey:String? = nil
    var enabled=true
    private var healthy:Bool {enabled && store.healthy && store.plan?.isCurrent(for:expectedDeviceKey)==true}
    var body: some View {
        TimelineView(.animation(minimumInterval:1/20,paused:!PreviewAnimationPolicy.shouldAnimate(visible:visible,healthy:healthy,frameCount:store.plan?.frames?.count ?? 0))) { context in
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Label(healthy && store.plan?.demo==true ? "演示中":healthy ? "实时灯效":"灯光预览",systemImage:"waveform.path").foregroundStyle(.cyan)
                    Spacer()
                    Text(title).foregroundStyle(.secondary)
                }.font(.caption)
                FunctionalKeyboardCanvas(plan:healthy ? store.plan:nil,date:context.date)
                    .frame(height:190)
                Text(healthy ? "显示实际发送帧；硬件刷新与省电状态可能略有差异。":"灯光未运行或数据过期")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(14).background(.black.opacity(0.22),in:RoundedRectangle(cornerRadius:12))
        }.background(PreviewVisibility { visible=$0;if $0 && enabled {store.start()} else {store.stop()} }).onDisappear { visible=false;store.stop() }.onChange(of:enabled) {_,value in if value && visible {store.start()} else {store.stop()}}
    }
    private var title: String {
        guard healthy,let p=store.plan else { return "示意图待更新" }
        if p.mode=="running" { return "\(p.taskCount ?? 0) 个任务 · \((RunningStyle(rawValue:p.style ?? "") ?? .classic).title(p.taskCount ?? 1))" }
        return ["complete-wave":"结束绿光上涌","complete-settle":"结束确认","reset-flash":"重置快闪","reset-glow":"重置收尾","brightness-test":"白光自检","idle":"等待任务","attention":"需要关注"][p.mode ?? ""] ?? "状态灯光"
    }
}

// Draw animated caps as one surface; avoid relaying out dozens of SwiftUI text views per frame.
struct FunctionalKeyboardCanvas:View {
    let plan:LightingPreviewData?
    let date:Date
    var body:some View {
        Canvas {context,size in
            func cap(_ label:String,_ key:String,_ rect:CGRect) {
                let rgb=plan?.rgb(key,at:date.timeIntervalSince1970) ?? (0,0,0)
                let color=Color(red:rgb.0,green:rgb.1,blue:rgb.2)
                let shape=Path(roundedRect:rect,cornerRadius:5)
                context.fill(shape,with:.color(color))
                context.stroke(shape,with:.color(.white.opacity(0.12)),lineWidth:1)
                let bright=0.2126*rgb.0+0.7152*rgb.1+0.0722*rgb.2>0.48
                context.draw(Text(label).font(.system(size:label=="G" ? 26:10,weight:.semibold,design:.rounded)).foregroundColor(bright ? .black.opacity(0.85):.white.opacity(0.85)),at:CGPoint(x:rect.midX,y:rect.midY))
            }
            let quotaWidth=(size.width-36)/10
            for i in 0..<10 {cap("F\(i+1)",String(58+i),CGRect(x:Double(i)*(quotaWidth+4),y:0,width:quotaWidth,height:28))}
            cap("G","logo",CGRect(x:0,y:85,width:54,height:54))
            let labels=[["Num","/","*"],["7","8","9"],["4","5","6"],["1","2","3"]]
            let ids=[[83,84,85],[95,96,97],[92,93,94],[89,90,91]]
            let left=78.0,top=40.0,w=34.0,h=26.0,gap=4.0
            for row in 0..<4 {for col in 0..<3 {cap(labels[row][col],String(ids[row][col]),CGRect(x:left+Double(col)*(w+gap),y:top+Double(row)*(h+gap),width:w,height:h))}}
            cap("0","98",CGRect(x:left,y:top+120,width:72,height:h));cap(".","99",CGRect(x:left+76,y:top+120,width:w,height:h))
            cap("−","86",CGRect(x:left+114,y:top,width:w,height:h))
            cap("+","87",CGRect(x:left+114,y:top+30,width:w,height:56))
            cap("↵","88",CGRect(x:left+114,y:top+90,width:w,height:56))
            context.draw(Text("F1–F10 · 额度\nLogo · 提醒\n小键盘 · 任务进度").font(.system(size:11)).foregroundColor(.secondary),at:CGPoint(x:max(300,size.width-100),y:110))
        }.accessibilityLabel("键盘状态示意图：F1 至 F10 显示额度，Logo 显示提醒，小键盘显示任务进度")
    }
}
