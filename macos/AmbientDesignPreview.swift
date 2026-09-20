import SwiftUI
import JavaScriptCore

@MainActor
final class AmbientPreviewRenderer:ObservableObject {
    private var context:JSContext?
    private var renderFunction:JSValue?
    private(set) var available=false
    init(){
        guard let url=Bundle.main.resourceURL?.appendingPathComponent("backend/scripts/ambient-engine.mjs"),let source=try? String(contentsOf:url,encoding:.utf8),let js=JSContext() else{return}
        js.evaluateScript(source.replacingOccurrences(of:"export ",with:""))
        guard js.exception == nil else{return}
        js.evaluateScript("function nativePreview(id,t,options) { const p=presets.find(p=>p.id===id); return p ? render(p,t,options) : {}; }")
        context=js;renderFunction=js.objectForKeyedSubscript("nativePreview");available=js.exception == nil
    }
    func frame(id:String,time:Double,options:[String:Any])->[String:[Double]] {
        guard available,let value=renderFunction?.call(withArguments:[id,time,options])?.toDictionary() else{return [:]}
        var frame:[String:[Double]]=[:]
        for (key,rgb) in value {if let key=key as? String,let rgb=rgb as? [NSNumber]{frame[key]=rgb.map{$0.doubleValue/255}}}
        return frame
    }
}

struct AmbientDesignPreview:View {
    @ObservedObject var model:PulseModel
    var previewWidth:CGFloat?=nil
    @StateObject private var renderer=AmbientPreviewRenderer()
    @State private var events:[[String:Any]]=[]
    @State private var paused=false
    @State private var visible=false
    @State private var settleAt=Date.distantPast
    @State private var reactiveAnimating=false
    @State private var heldTime=0.0
    @State private var offset=0.0
    private var preset:AmbientPreset? {AmbientCatalog.shared.presets.first{$0.id==model.preferences.ambientPreset}}
    private func time(_ date:Date)->Double {paused ? heldTime:date.timeIntervalSinceReferenceDate-offset}
    private func press(_ id:String){let t=time(Date());events=events.filter{t-($0["at"] as? Double ?? 0)<8};events.append(["id":Int(id).map{$0 as Any} ?? id,"at":t]);events=Array(events.suffix(64));scheduleSettle()}
    private func scheduleSettle(){
        let remaining=max(0,(events.compactMap{$0["at"] as? Double}.max() ?? 0)+8-time(Date()))
        reactiveAnimating=remaining>0
        settleAt=Date().addingTimeInterval(remaining)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            TimelineView(.animation(minimumInterval:1/15,paused:paused || !visible || (preset?.category != "loop" && !(preset?.category == "reactive" && reactiveAnimating)))){timeline in
                let t=time(timeline.date)
                let frame=renderer.frame(id:model.preferences.ambientPreset,time:t,options:["palette":model.preferences.ambientPalette,"profile":model.preferences.ambientProfile,"period":model.preferences.ambientPeriod,"zones":model.preferences.ambientZones,"brightness":model.preferences.globalBrightness*model.preferences.otherBrightness,"events":events])
                GeometryReader { geometry in
                    let scale=geometry.size.width/24.8
                    ZStack(alignment:.topLeading){ForEach(AmbientCatalog.shared.keys){key in
                        let c=frame[key.id] ?? [0.07,0.08,0.1]
                        Button {press(key.id)} label:{
                            Text(key.label).font(.system(size:key.label.count>3 ? 7:9)).foregroundStyle(0.2126*c[0]+0.7152*c[1]+0.0722*c[2]>0.55 ? Color.black:Color.white)
                                .frame(width:(key.w-0.09)*scale,height:(key.h-0.1)*scale)
                                .background(Color(red:c[0],green:c[1],blue:c[2]),in:RoundedRectangle(cornerRadius:3))
                                .overlay(RoundedRectangle(cornerRadius:3).stroke(.gray.opacity(key.protected ? 0.25:0.7),lineWidth:0.6))
                        }.buttonStyle(.plain).disabled(key.protected || paused)
                            .accessibilityLabel(key.label+(key.protected ? " 功能区占位":" 模拟按键"))
                            .offset(x:(key.x+1.7)*scale,y:key.y*scale)
                    }}
                }.aspectRatio(24.8/6.5,contentMode:.fit).frame(width:previewWidth,height:previewWidth.map{$0*6.5/24.8})
            }
            HStack {
                Button(paused ? "继续预览":"暂停预览"){
                    if paused {offset=Date().timeIntervalSinceReferenceDate-heldTime;paused=false;scheduleSettle()}
                    else {heldTime=time(Date());paused=true}
                }.controlSize(.small)
                if preset?.category == "reactive" {
                    Button("模拟 G1–G5"){
                        let t=time(Date());events=(1...5).map{["id":"G\($0)","at":t+Double($0-1)*0.4]};scheduleSettle()
                    }.controlSize(.small).disabled(paused)
                    Button("模拟主键输入"){
                        let t=time(Date());events=[4,22,7,9,10,11,13,14,15,44].enumerated().map{["id":$0.element,"at":t+Double($0.offset)*0.18]};scheduleSettle()
                    }.controlSize(.small).disabled(paused)
                }
            }
            Text(renderer.available ? "设计预览 · 功能区为占位；点击键帽仅模拟画面，不发送按键。":"预览引擎不可用，请检查应用资源。")
                .font(.caption).foregroundStyle(.secondary)
        }.background(PreviewVisibility {visible=$0}).onDisappear {visible=false}
        .onChange(of:model.preferences.ambientPreset){_,_ in events=[];reactiveAnimating=false}
        .task(id:settleAt) {
            let delay=settleAt.timeIntervalSinceNow
            guard delay>0 else{return}
            do {try await Task.sleep(for:.seconds(delay))}catch{return}
            if !paused {reactiveAnimating=false}
        }
    }
}
