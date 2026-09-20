import SwiftUI
import AppKit
import Network
import CoreGraphics

@MainActor
final class AmbientInput:ObservableObject {
    static let shared=AmbientInput()
    @Published var status="全局按键交互未开启"
    let signature=InputSignature.current()
    private(set) var baseline:InputAuthorizationBaseline?
    @Published private(set) var continuity="unknown"
    @Published private(set) var assessment=InputMonitorState.assess(requested:false,preflight:false,tapActive:false,continuity:"unknown")
    @Published private(set) var checkedAt=Date.distantPast
    @Published private(set) var preflight=false
    @Published private(set) var tapActive=false
    private var savedSuccess=false
    init(){
        baseline=InputAuthorizationBaseline.read(PulsePaths.data.appendingPathComponent("input-authorized-identity.json"))
        if baseline == nil, let url=Bundle.main.url(forResource:"input-install-baseline",withExtension:"json") {
            baseline=InputAuthorizationBaseline.read(url)
        }
        continuity=InputSignature.continuity(with:baseline?.signature)
    }
    private var tap:CFMachPort?,source:CFRunLoopSource?
    private var connection:NWConnection?
    private var requested=false
    @Published private(set) var capturedCount=0
    private var deliveredCount=0
    private var lastPublish=Date.distantPast
    private var lastAttempt=Date.distantPast
    private func publish(force:Bool=false){
        let now=Date();guard force || now.timeIntervalSince(lastPublish)>=1 else{return};lastPublish=now
        tapActive=tap.map{CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap:$0)} ?? false
        checkedAt=now
        assessment=InputMonitorState.assess(requested:requested,preflight:preflight,tapActive:tapActive,continuity:continuity)
        status=assessment.title
        var value:[String:Any]=["at":now.timeIntervalSince1970,"pid":ProcessInfo.processInfo.processIdentifier,"appPath":Bundle.main.bundlePath,"requested":requested,"preflight":preflight,"tapActive":tapActive,"capturedCount":capturedCount,"deliveredCount":deliveredCount,"status":status,"state":assessment.code,"continuity":continuity,"baselineSource":baseline?.source ?? "none","guidance":assessment.guidance]
        if let signature, let data=try? JSONEncoder().encode(signature),let object=try? JSONSerialization.jsonObject(with:data){value["signature"]=object}
        if tapActive && !savedSuccess, let signature {
            let record=InputAuthorizationBaseline(signature:signature,source:"verified_live_listener",at:now.timeIntervalSince1970)
            if let data=try? JSONEncoder().encode(record) {
                do {try data.write(to:PulsePaths.data.appendingPathComponent("input-authorized-identity.json"),options:.atomic);savedSuccess=true} catch {value["baselineWriteError"]="无法保存本机验证记录"}
            }
        }
        if let data=try? JSONSerialization.data(withJSONObject:value){try? data.write(to:PulsePaths.data.appendingPathComponent("input-status.json"),options:.atomic)}
    }
    // Physical ANSI key positions only; no text, clipboard or macro assignments are read.
    private let hid:[Int:Int]=[0:4,1:22,2:7,3:9,4:11,5:10,6:29,7:27,8:6,9:25,11:5,12:20,13:26,14:8,15:21,16:28,17:23,18:30,19:31,20:32,21:33,22:35,23:34,24:46,25:38,26:36,27:45,28:37,29:39,30:48,31:18,32:24,33:47,34:12,35:19,36:40,37:15,38:13,39:52,40:14,41:51,42:49,43:54,44:56,45:17,46:16,47:55,48:43,49:44,50:53,51:42,53:41,103:68,111:69,115:74,116:75,117:76,119:77,121:78,123:80,124:79,125:81,126:82]
    func send(_ id:String,preview:Bool=true,deviceKey:String?=nil) {
        if connection == nil {let c=NWConnection(host:"127.0.0.1",port:49315,using:.udp);c.start(queue:.main);connection=c}
        let value:Any=Int(id).map{$0 as Any} ?? id
        var payload:[String:Any]=["id":value,"source":preview ? "preview":"physical"]
        if preview,let deviceKey {payload["deviceKey"]=deviceKey}
        guard let data=try? JSONSerialization.data(withJSONObject:payload) else{return}
        connection?.send(content:data,completion:.contentProcessed({error in
            Task{@MainActor in if !preview && error == nil {self.deliveredCount+=1;self.publish()}}
        }))
    }
    func receive(_ code:Int){guard requested,let id=hid[code] else{return};capturedCount+=1;send(String(id),preview:false);publish()}
    func recheck(){lastAttempt = .distantPast;stop();configure(requested)}
    func openPrivacySettings(){if let url=URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"){NSWorkspace.shared.open(url)}}
    func requestPermission(){_ = CGRequestListenEventAccess();lastAttempt = .distantPast;configure(requested)}
    func configure(_ enabled:Bool){
        requested=enabled
        preflight=CGPreflightListenEventAccess()
        guard enabled else {stop();publish();return}
        if let tap, !CFMachPortIsValid(tap) {stop()}
        if let tap {CGEvent.tapEnable(tap:tap,enable:true);status=InputMonitorState.status(requested:true,preflight:preflight,tapActive:CGEvent.tapIsEnabled(tap:tap));publish();return}
        guard Date().timeIntervalSince(lastAttempt)>=5 else{return};lastAttempt=Date()
        // Creation is still enforced by macOS. Preflight is diagnostic, not a substitute for its result.
        let mask=CGEventMask(1)<<CGEventType.keyDown.rawValue
        guard let created=CGEvent.tapCreate(tap:.cgSessionEventTap,place:.headInsertEventTap,options:.listenOnly,eventsOfInterest:mask,callback:{_,type,event,_ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                Task{@MainActor in AmbientInput.shared.recheck()}
            }
            if type == .keyDown {
                let code=Int(event.getIntegerValueField(.keyboardEventKeycode))
                if event.getIntegerValueField(.keyboardEventAutorepeat)==0 {Task{@MainActor in AmbientInput.shared.receive(code)}}
            }
            return Unmanaged.passUnretained(event)
        },userInfo:nil) else {status=InputMonitorState.status(requested:true,preflight:preflight,tapActive:false);publish(force:true);return}
        tap=created;source=CFMachPortCreateRunLoopSource(kCFAllocatorDefault,created,0)
        if let source {CFRunLoopAddSource(CFRunLoopGetMain(),source,.commonModes)}
        CGEvent.tapEnable(tap:created,enable:true);status=InputMonitorState.status(requested:true,preflight:preflight,tapActive:CGEvent.tapIsEnabled(tap:created));publish(force:true)
    }
    private func stop(){if let tap {CGEvent.tapEnable(tap:tap,enable:false);CFMachPortInvalidate(tap)};if let source {CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes)};tap=nil;source=nil}
}

struct AmbientKeyboardView:View {
    @StateObject private var store=LightingDiagramStore()
    @State private var visible=false
    let enabled:Bool
    var expectedDeviceKey:String? = nil
    var previewWidth:CGFloat?=nil
    private var healthy:Bool {enabled && store.healthy && store.plan?.isCurrent(for:expectedDeviceKey)==true}
    var body:some View {
        TimelineView(.animation(minimumInterval:1/15,paused:!PreviewAnimationPolicy.shouldAnimate(visible:visible,healthy:healthy,frameCount:store.plan?.frames?.count ?? 0))) { context in
            GeometryReader { geometry in
                let scale=geometry.size.width/24.8
                ZStack(alignment:.topLeading) {
                    ForEach(AmbientCatalog.shared.keys) { key in
                        let rgb=healthy ? store.plan?.rgb(key.id,at:context.date.timeIntervalSince1970) ?? (0,0,0):(0,0,0)
                        Button { AmbientInput.shared.send(key.id,deviceKey:expectedDeviceKey) } label: {
                            Text(key.label).font(.system(size:key.label.count>3 ? 7:9)).foregroundStyle(0.2126*rgb.0+0.7152*rgb.1+0.0722*rgb.2>0.55 ? Color.black:Color.white)
                                .frame(width:max(1,(key.w-0.09)*scale),height:max(1,(key.h-0.1)*scale))
                                .background(Color(red:rgb.0,green:rgb.1,blue:rgb.2),in:RoundedRectangle(cornerRadius:3))
                                .overlay(RoundedRectangle(cornerRadius:3).stroke(.gray.opacity(key.protected ? 0.3:0.7),lineWidth:0.6))
                        }.buttonStyle(.plain).disabled(key.protected || !enabled || !healthy)
                            .accessibilityLabel(key.label+(key.protected ? " 功能区":" 交互测试"))
                            .offset(x:(key.x+1.7)*scale,y:key.y*scale)
                    }
                }
            }.aspectRatio(24.8/6.5,contentMode:.fit).frame(width:previewWidth,height:previewWidth.map{$0*6.5/24.8})
        }.background(PreviewVisibility {visible=$0;if $0 && enabled {store.start()} else {store.stop()}}).onDisappear{visible=false;store.stop()}.onChange(of:enabled){_,value in if value && visible {store.start()} else {store.stop()}}
        Text(healthy ? "显示实际发送帧；交互预设可点击键帽测试。":"键盘未连接或预览不可用。")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct AmbientSettingsView:View {
    @ObservedObject var model:PulseModel
    var compactControls=false
    @State private var category="all"
    private let catalog=AmbientCatalog.shared
    private var preset:AmbientPreset? {catalog.presets.first{$0.id==model.preferences.ambientPreset}}
    private func pick(_ id:String){guard let p=catalog.presets.first(where:{$0.id==id}) else{return}
        model.setPreference(\.ambientPreset,p.id);model.setPreference(\.ambientPalette,p.palette)
        model.setPreference(\.ambientProfile,p.profile);model.setPreference(\.ambientPeriod,p.period);model.setPreference(\.ambientZones,[:])
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12){
            if !compactControls {
            Text("非功能区 · 48 个预设").font(.headline)
            Toggle("启用非功能区预设（含 G1–G5）",isOn:Binding(get:{model.preferences.ambientEnabled},set:{model.setPreference(\.ambientEnabled,$0)}))
            Picker("分类",selection:$category){Text("全部").tag("all");Text("G1–G5 联动").tag("gkeys");Text("静态").tag("static");Text("循环").tag("loop");Text("分区").tag("zones");Text("交互").tag("reactive")}
            Picker("预设",selection:Binding(get:{model.preferences.ambientPreset},set:{pick($0)})){
                ForEach(catalog.presets.filter{category=="all" || (category=="gkeys" ? $0.gkeyFocus:$0.category==category) || $0.id==model.preferences.ambientPreset}){p in Text(p.name).tag(p.id)}
            }
            Text(preset?.description ?? "灯效目录不可用").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment:.leading,spacing:12) {
                Picker("色板",selection:Binding(get:{model.preferences.ambientPalette},set:{model.setPreference(\.ambientPalette,$0)})){ForEach(catalog.palettes.keys.sorted(),id:\.self){id in Text(catalog.palettes[id]!.name).tag(id)}}
                Picker("亮度布局",selection:Binding(get:{model.preferences.ambientProfile},set:{model.setPreference(\.ambientProfile,$0);model.setPreference(\.ambientZones,[:])})){ForEach(catalog.profiles.keys.sorted(),id:\.self){id in Text(catalog.profiles[id]!.name).tag(id)}}
            }
            if preset?.category == "loop" || preset?.category == "reactive" {
                HStack {Text("循环 / 响应时长");Slider(value:Binding(get:{model.preferences.ambientPeriod},set:{model.setPreference(\.ambientPeriod,$0)}),in:1...(preset?.category == "reactive" ? 8:24),step:0.2);Text("\(model.preferences.ambientPeriod,specifier:"%.1f") 秒").monospacedDigit()}
                if ["heat","trail"].contains(preset?.effect ?? "") {Text("热图与足迹在 8 秒内衰减，时长滑块不影响这两项。").font(.caption).foregroundStyle(.secondary)}
            }
            DisclosureGroup("八个分区亮度"){
                ForEach(catalog.zones){zone in
                    let value=model.preferences.ambientZones[zone.id] ?? catalog.profiles[model.preferences.ambientProfile]?.values[zone.id] ?? 1
                    HStack {Text(zone.name).frame(width:120,alignment:.leading);Slider(value:Binding(get:{value},set:{newValue in var zones=model.preferences.ambientZones;zones[zone.id]=newValue;model.setPreference(\.ambientZones,zones)}),in:0...1,step:0.01);Text("\(value*100,specifier:"%.0f")%").monospacedDigit().frame(width:40)}
                }
            }
            if !compactControls { AmbientKeyboardView(enabled:model.preferences.ambientEnabled && model.lightingActive,expectedDeviceKey:model.selectedDeviceKey) }
            if preset?.category == "reactive" {
                Toggle("响应普通键盘输入",isOn:Binding(get:{model.preferences.ambientInputEnabled},set:{model.setPreference(\.ambientInputEnabled,$0)}))
                InputAuthorizationView()
                Text("按键事件仅在内存中短暂保留，不记录文字。实体 G1–G5 独立按下事件暂不支持；主键输入可驱动 G 区，点击 G 键帽可测试反向联动。Secure Input 下系统可能暂停输入通知。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


struct InputAuthorizationView:View {
    @ObservedObject private var input=AmbientInput.shared
    var body:some View {
        VStack(alignment:.leading,spacing:7){
            Label(input.assessment.title,systemImage:input.tapActive ? "checkmark.shield":"keyboard")
                .foregroundStyle(input.assessment.needsPermission ? Color.orange:Color.secondary)
            Text(input.assessment.guidance).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button("重新检查"){input.recheck()}
                if input.assessment.needsPermission { Button("打开输入监控设置"){input.openPrivacySettings()} }
            }
            Text("已接收 \(input.capturedCount) 次普通按键 · 检查于 \(input.checkedAt == .distantPast ? "尚未检查":input.checkedAt.formatted(date:.omitted,time:.standard))")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("授权检查详情") {
                VStack(alignment:.leading,spacing:5){
                    Text("权限预检：\(input.preflight ? "允许":"未允许") · 实际监听：\(input.tapActive ? "已启用":"未启用")")
                    Text("签名连续性：\(input.continuity == "matches" ? "符合之前身份":input.continuity == "changed" ? "不符合之前身份":"无可用记录")")
                    Text("对照来源：\(input.baseline?.source == "verified_live_listener" ? "本机上次监听成功记录":input.baseline == nil ? "无":"构建前安装版本（不是 TCC 记录）")")
                    Text("当前 app：\(Bundle.main.bundlePath)").textSelection(.enabled)
                    Text("CDHash：\(input.signature?.cdhash ?? "无法读取")").textSelection(.enabled)
                    Text("签名：\(input.signature?.team ?? "无法读取")")
                    Text("系统未公开 TCC 条目的签名绑定查询；签名对照只说明连续性，当前授权以实际监听为准。这里只记录计数，不保存按键文字。")
                    Button("在 Finder 中显示当前 app"){NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])}
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
