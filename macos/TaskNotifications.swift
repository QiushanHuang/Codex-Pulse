import AppKit
import SwiftUI
import UserNotifications
import QuartzCore

struct TaskReminderSettings:View {
    @ObservedObject var model:PulseModel
    @ObservedObject var reminders:TaskNotificationController
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("任务提醒").font(.headline)
            Text("通知方式").font(.subheadline)
            Picker("通知方式",selection:Binding(get:{model.notificationPreferences.delivery},set:{mode in
                var preferences=model.notificationPreferences;preferences.delivery=mode
                model.saveNotificationPreferences(["systemEnabled":preferences.systemEnabled,"cardsEnabled":preferences.cardsEnabled])
            })) {
                ForEach(NotificationDelivery.allCases){mode in Text(mode.label).tag(mode)}
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("通知方式")
            Text(model.notificationPreferences.delivery.detail).font(.caption).foregroundStyle(.secondary)
            Toggle("提醒提示音",isOn:Binding(get:{model.notificationPreferences.soundEnabled},set:{model.saveNotificationPreferences(["soundEnabled":$0])}))
                .disabled(model.notificationPreferences.delivery == .off)
            ForEach(ReminderEvent.allCases) {event in
                HStack {
                    Text(event.label).frame(width:85,alignment:.leading)
                    Picker(event.label,selection:Binding(get:{model.notificationPreferences.sound(for:event)},set:{sound in
                        var selections=model.notificationPreferences.soundSelections
                        selections[event.rawValue]=sound.rawValue
                        model.saveNotificationPreferences(["soundSelections":selections])
                    })) {
                        ForEach(ReminderSound.allCases) {sound in Text(sound.label).tag(sound)}
                    }.labelsHidden().accessibilityLabel(event.label+"提示音")
                    Button("试听") {reminders.previewSound(model.notificationPreferences.sound(for:event))}
                        .disabled(model.notificationPreferences.sound(for:event) == .silent)
                        .accessibilityLabel("试听"+event.label+"提示音")
                }
            }
            Text("每类事件可独立选音或静音，试听不受总开关限制。同时到来的提醒优先播放失败、审批、问答提示音；音量跟随当前输出。").font(.caption).foregroundStyle(.secondary)
            if let notice=reminders.soundNotice {Text(notice).font(.caption).foregroundStyle(.orange)}
            if model.notificationPreferences.systemEnabled {
                HStack {
                    Text("macOS 通知："+reminders.authorization).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("允许系统通知"){reminders.requestAuthorization()}
                    Button("macOS 通知设置") {
                        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                }
            }
            Text("轮次结束会提示；点击卡片或通知可进入对应任务。侧边卡片在事件发生时短暂滑入，跟随侧边栏的屏幕和方向，不抢走输入焦点。").font(.caption).foregroundStyle(.secondary)
            Button(model.hookConnectionBusy ? "正在连接…":"连接 Codex 权限与问题提醒") {model.connectTaskSignals()}
                .disabled(model.hookConnectionBusy)
            Text("连接会备份并添加 ~/.codex/hooks.json，需要在 Codex 的 Hooks 中审阅、信任。只传递任务 ID 和状态，不会代你授权或回答。完成提醒不需要此连接。").font(.caption).foregroundStyle(.secondary)
            if let notice=model.hookNotice {Text(notice).font(.caption).foregroundStyle(.orange)}
            if model.notificationPreferences.cardsEnabled {
                Button("预览 Pulse 卡片") {
                    let alert=TaskAlert(id:UUID().uuidString,taskID:"",kind:"waiting_input",at:Date().timeIntervalSince1970,title:"提示预览 · 需要你回答")
                    reminders.present(alert)
                }
            }
        }
    }
}

struct TaskAlertCard:View {
    let alert:TaskAlert
    var open:()->Void
    var dismiss:()->Void
    private var tint:Color {(alert.kind=="completed" || alert.kind=="reset") ? pulseMint:alert.kind=="waiting_input" ? .cyan:alert.kind=="failed" ? .red:.orange}
    var body:some View {
        HStack(alignment:.top,spacing:13) {
            Image(systemName:alert.symbol).font(.system(size:23,weight:.medium))
                .foregroundStyle(tint).frame(width:42,height:42)
                .background(tint.opacity(0.12),in:RoundedRectangle(cornerRadius:13))
            Button(action:open) {
                VStack(alignment:.leading,spacing:5) {
                    HStack {
                        Text(alert.heading).font(.system(size:11,weight:.semibold)).foregroundStyle(tint)
                        Spacer()
                        Text("CODEX PULSE").font(.system(size:8,weight:.medium,design:.monospaced)).tracking(1).foregroundStyle(.secondary)
                    }
                    Text(alert.title).font(.system(size:14,weight:.semibold)).foregroundStyle(.primary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Text(alert.detail).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action:dismiss) {Image(systemName:"xmark").font(.system(size:9,weight:.bold)).frame(width:20,height:20)}
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("关闭提示")
        }.padding(17)
            .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:22,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:22).strokeBorder(LinearGradient(colors:[tint.opacity(0.5),.white.opacity(0.15)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:1))
            .shadow(color:tint.opacity(0.12),radius:18,y:5)
            .padding(12).frame(width:392)
            .accessibilityElement(children:.contain)
    }
}

final class TaskAlertPanel:NSPanel {
    override var canBecomeKey:Bool {false}
    override var canBecomeMain:Bool {false}
}

@MainActor final class TaskAlertAudio {
    private var tone:NSSound?
    @discardableResult func play(_ sound:ReminderSound)->Bool {
        tone?.stop()
        guard let path=sound.path else {tone=nil;return true}
        guard let next=NSSound(contentsOfFile:path,byReference:true) else {return false}
        tone=next;next.volume=0.4
        return next.play()
    }
}

@MainActor final class TaskNotificationController:NSObject,ObservableObject,UNUserNotificationCenterDelegate {
    @Published private(set) var authorization="尚未授权"
    @Published private(set) var soundNotice:String?
    private var preferences=NotificationPreferences()
    private var policy=TaskAlertPolicy()
    private let enabled:Bool
    private var panels:[String:NSPanel]=[:]
    private var expirations:[String:DispatchWorkItem]=[:]
    private var alerts:[TaskAlert]=[]
    private var canPresent=false
    private var latestStatuses:[String:String]=[:]
    private var soundPolicy=TaskSoundPolicy()
    private let audio=TaskAlertAudio()
    private var openTask:(String)->Void
    var sidebarPreferences=DesktopPreferences()
    init(enabled:Bool,openTask:@escaping (String)->Void) {
        self.enabled=enabled;self.openTask=openTask;super.init()
        if enabled {UNUserNotificationCenter.current().delegate=self;refreshAuthorization()}
    }
    func configure(_ next:NotificationPreferences) {
        if preferences.cardsEnabled && !next.cardsEnabled {dismissAll()}
        if enabled && preferences.systemEnabled && !next.systemEnabled {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        preferences=next
    }
    func refreshAuthorization() {
        guard enabled else{return}
        UNUserNotificationCenter.current().getNotificationSettings{[weak self] settings in
            let text=settings.authorizationStatus == .authorized ? "已允许":settings.authorizationStatus == .denied ? "系统已关闭":"尚未授权"
            Task{@MainActor in self?.authorization=text}
        }
    }
    func requestAuthorization() {
        guard enabled else{return}
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]){[weak self] _,_ in
            Task{@MainActor in self?.refreshAuthorization()}
        }
    }
    func previewSound(_ sound:ReminderSound) {
        soundNotice=audio.play(sound) ? nil:"提示音未能播放，请检查声音输出设备。"
    }
    func consume(_ snapshot:PulseSnapshot,running:Bool) {
        let events=snapshot.events.compactMap{event -> TaskAlert? in
            if event.kind == "reset",snapshot.quotaError == nil {
                return TaskAlert(id:"reset:\(event.at):\(event.message)",taskID:"",kind:"reset",at:event.at,title:event.message)
            }
            guard let id=event.id,let taskID=event.taskId,UUID(uuidString:taskID) != nil,
                  ["completed","waiting_approval","waiting_input","failed","interrupted"].contains(event.kind) else{return nil}
            if event.kind.hasPrefix("waiting_") && !snapshot.tasks.contains(where:{$0.id==taskID && $0.status==event.kind}) {return nil}
            return TaskAlert(id:id,taskID:taskID,kind:event.kind,at:event.at,title:event.message)
        }
        let next=policy.consume(events,now:Date().timeIntervalSince1970)
        latestStatuses=Dictionary(snapshot.tasks.map{($0.id,$0.status)},uniquingKeysWith:{_,new in new})
        canPresent=enabled && running && snapshot.taskError==nil && Date().timeIntervalSince1970-snapshot.generatedAt<30
        guard canPresent else{dismissAll();return}
        for alert in alerts {
            let status=snapshot.tasks.first{$0.id==alert.taskID}?.status
            if alert.resolved(taskStatus:status) {dismiss(alert.id)}
        }
        if let sound=preferences.soundCandidate(in:next),
           soundPolicy.consume(enabled:true,at:ProcessInfo.processInfo.systemUptime) {previewSound(sound)}
        for alert in next {
            if preferences.cardsEnabled {
                // PulseModel can consume its first snapshot while SwiftUI constructs
                // the StateObject. Create floating NSHostingViews after that graph update.
                DispatchQueue.main.async {[weak self] in
                    guard let self,self.canPresent,self.preferences.cardsEnabled,
                          !alert.resolved(taskStatus:self.latestStatuses[alert.taskID]) else{return}
                    self.present(alert)
                }
            }
            // macOS enforces permission; do not drop startup alerts before the async settings read completes.
            if preferences.systemEnabled {send(alert)}
        }
    }
    private func send(_ alert:TaskAlert) {
        let content=UNMutableNotificationContent()
        content.title=alert.heading;content.body=alert.title
        content.subtitle=alert.kind=="reset" ? "服务端已确认额度重置":alert.kind=="completed" ? "轮次结束，点击查看结果":"点击前往 Codex 处理"
        content.threadIdentifier=alert.taskID;content.userInfo=["taskId":alert.taskID]
        // Pulse owns the short cue so cards can sound even when system banners
        // are suppressed. Keep this content silent to avoid a second playback.
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:alert.id,content:content,trigger:nil))
    }
    func present(_ alert:TaskAlert) {
        for previous in alerts where previous.taskID==alert.taskID {dismiss(previous.id)}
        while alerts.count>=3 {dismiss(alerts[0].id)}
        let panel=TaskAlertPanel(contentRect:NSRect(x:0,y:0,width:392,height:140),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed=false;panel.isOpaque=false;panel.backgroundColor = .clear
        panel.level = .floating;panel.hasShadow=false;panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        panel.isMovableByWindowBackground=false
        let view=NSHostingView(rootView:TaskAlertCard(alert:alert,open:{[weak self] in
            if UUID(uuidString:alert.taskID) != nil {self?.openTask(alert.taskID)}
            self?.dismiss(alert.id)
        },dismiss:{[weak self] in self?.dismiss(alert.id)}))
        let size=view.fittingSize
        panel.setContentSize(NSSize(width:392,height:max(128,size.height)));panel.contentView=view
        panels[alert.id]=panel;alerts.append(alert);positionPanels()
        let target=panel.frame
        let reduceMotion=NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !reduceMotion {
            panel.setFrame(target.offsetBy(dx:sidebarPreferences.sidebarSide == .left ? -28:28,dy:0),display:false);panel.alphaValue=0
        }
        panel.orderFrontRegardless()
        if !reduceMotion {
            NSAnimationContext.runAnimationGroup{context in
                context.duration=0.24;context.timingFunction=CAMediaTimingFunction(name:.easeOut)
                panel.animator().setFrame(target,display:true);panel.animator().alphaValue=1
            }
        }
        let expiry=DispatchWorkItem{[weak self] in MainActor.assumeIsolated{self?.dismiss(alert.id)}}
        expirations[alert.id]=expiry
        DispatchQueue.main.asyncAfter(deadline:.now()+(alert.kind.hasPrefix("waiting_") ? 18:9),execute:expiry)
    }
    private func positionPanels() {
        let screen=NSScreen.screens.first{SidebarController.screenID($0)==sidebarPreferences.sidebarScreenID} ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else{return}
        var top=screen.visibleFrame.maxY-18
        for alert in alerts.reversed() {
            guard let panel=panels[alert.id] else{continue}
            let x=sidebarPreferences.sidebarSide == .left ? screen.visibleFrame.minX+12:screen.visibleFrame.maxX-panel.frame.width-12
            panel.setFrameOrigin(NSPoint(x:x,y:top-panel.frame.height));top-=panel.frame.height+2
        }
    }
    func dismiss(_ id:String) {
        expirations.removeValue(forKey:id)?.cancel();panels.removeValue(forKey:id)?.close()
        alerts.removeAll{$0.id==id};positionPanels()
    }
    func dismissAll() {for id in Array(panels.keys) {dismiss(id)}}
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler completionHandler:@escaping ()->Void) {
        if let tid=response.notification.request.content.userInfo["taskId"] as? String,UUID(uuidString:tid) != nil {
            Task{@MainActor [weak self] in self?.openTask(tid)}
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler completionHandler:@escaping (UNNotificationPresentationOptions)->Void) {
        Task{@MainActor [weak self] in completionHandler(self?.preferences.systemEnabled == true ? [.banner,.list]:[])}
    }
}
