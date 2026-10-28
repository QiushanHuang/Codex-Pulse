import SwiftUI
import AppKit
import WidgetKit

struct LightPreferences: Codable, Equatable {
    var globalBrightness=1.0, quotaBrightness=1.0, logoBrightness=1.0, keypadBrightness=1.0, otherBrightness=1.0
    var ambientEnabled=false, ambientInputEnabled=false
    var ambientPreset="g-ladder", ambientPalette="glacier", ambientProfile="balanced"
    var ambientPeriod=12.0
    var ambientZones:[String:Double]=[:]
    var cycleSeconds=12.0
    var otherColorEnabled=false
    var otherColor="#FFC284"
    var lowAlertEnabled=true
    var idleAfterSeconds=60.0, idleBrightness=0.5, sleepAfterSeconds=300.0
    var mode1="comet", mode2="wave", mode3="wave", mode4="ripple"
    init(_ values: [String:Any] = [:]) {
        func number(_ key:String,_ fallback:Double,_ minimum:Double=0,_ maximum:Double=1)->Double {
            guard let value=values[key] as? Double,value.isFinite else { return fallback }
            return max(minimum,min(maximum,value))
        }
        globalBrightness=number("globalBrightness",1);quotaBrightness=number("quotaBrightness",1)
        logoBrightness=number("logoBrightness",1);keypadBrightness=number("keypadBrightness",1);otherBrightness=number("otherBrightness",1)
        ambientEnabled=values["ambientEnabled"] as? Bool ?? false
        ambientInputEnabled=values["ambientInputEnabled"] as? Bool ?? false
        ambientPreset=values["ambientPreset"] as? String ?? "g-ladder"
        ambientPalette=values["ambientPalette"] as? String ?? "glacier"
        ambientProfile=values["ambientProfile"] as? String ?? "balanced"
        ambientPeriod=number("ambientPeriod",12,1,24)
        ambientZones=(values["ambientZones"] as? [String:Double] ?? [:]).filter{$0.value.isFinite}.mapValues{max(0,min(1,$0))}
        cycleSeconds=number("cycleSeconds",12,2,30)
        otherColorEnabled=values["otherColorEnabled"] as? Bool ?? false
        if let value=values["otherColor"] as? String,value.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil { otherColor=value.uppercased() }
        lowAlertEnabled=values["lowAlertEnabled"] as? Bool ?? true
        idleAfterSeconds=number("idleAfterSeconds",60,30,1800).rounded()
        idleBrightness=number("idleBrightness",0.5)
        sleepAfterSeconds=max(idleAfterSeconds+30,number("sleepAfterSeconds",300,60,7200).rounded())
        mode1=validStyle(values["mode1"],fallback:.comet);mode2=validStyle(values["mode2"],fallback:.wave)
        mode3=validStyle(values["mode3"],fallback:.wave);mode4=validStyle(values["mode4"],fallback:.ripple)
    }
    private func validStyle(_ value:Any?,fallback:RunningStyle)->String { RunningStyle(rawValue:value as? String ?? "")?.rawValue ?? fallback.rawValue }
    func style(_ count:Int)->RunningStyle { RunningStyle(rawValue:[mode1,mode2,mode3,mode4][max(0,min(3,count-1))]) ?? .wave }
    var dictionary: [String:Any] { (try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:] }
    var ambientColor: Color {
        let hex=UInt32(otherColor.dropFirst(),radix:16) ?? 0xFFC284
        return Color(.sRGB,red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255,opacity:1)
    }
}

@MainActor
final class PulseModel: ObservableObject {
    @Published var snapshot=PulseSnapshot.read()
    @Published var running=false
    @Published var resetBusy=false
    @Published var resetResult:QuotaResetResult?
    @Published var quotaRefreshRequestedAt:Double=0
    private var resetChild:Process?
    @Published var lighting=false
    @Published var previewScene:String?
    @Published var preferences=LightPreferences()
    @Published var menuBarPreferences=MenuBarPreferences()
    @Published var notificationPreferences=NotificationPreferences()
    @Published var quotaNotificationPreferences=QuotaNotificationPreferences()
    @Published var hookConnectionBusy=false
    @Published var hookNotice:String?
    private var hookChild:Process?
    @Published var error:String?
    @Published var configurationNotice:String?
    @Published var settingsCategory:SettingsCategory = .general
    @Published var route:WorkbenchRoute = .overview
    @Published var appearance:PulseAppearance = .system
    @Published var stickyPinned=false
    @Published var desktopPreferences=DesktopPreferences()
    @Published var deviceInventory=DeviceInventory.empty
    @Published var selectedDeviceKey:String?
    let windows=PulseWindowCoordinator()
    private(set) var statusBar:PulseStatusBar?
    private(set) var sidebar:SidebarController?
    private(set) var stickyExpansion:StickyExpansionController?
    private(set) var reminders:TaskNotificationController?
    private var snapshotObserver:SnapshotObserver?
    private var child:Process?
    private var timer:Timer?
    private var lastReload=Date.distantPast
    private var settingsSave:Timer?
    private let configuration:PulseConfigurationStore
    private var lastConfig:[String:Any]=[:]
    private var monitoringAllowed=true
    private var monitoringRequested=false

    var selectedDevice:KeyboardDevice? {deviceInventory.devices.first{$0.key==selectedDeviceKey}}
    var deviceReady:Bool { deviceInventory.status == "ready" && !deviceInventory.isStale() && selectedDevice?.selectable==true && selectedDevice?.isVerified==true }
    var lightingActive:Bool {lighting && deviceReady && deviceInventory.activeKey==selectedDeviceKey && snapshot.keyboard.status=="connected" && Date().timeIntervalSince1970-snapshot.generatedAt<30}
    var inputRequested:Bool {running && lighting && deviceReady && deviceInventory.activeKey==selectedDeviceKey && preferences.ambientEnabled && preferences.ambientInputEnabled && AmbientCatalog.shared.presets.first{$0.id==preferences.ambientPreset}?.category == "reactive"}

    init(startMonitoring:Bool=true,configurationDirectory:URL=PulsePaths.data) {
        configuration=PulseConfigurationStore(directory:configurationDirectory)
        monitoringAllowed=startMonitoring
        do {
            let backup=PulsePaths.data.appendingPathComponent("keyboard-backup.json")
            let record=(try? Data(contentsOf:backup)).flatMap{try? JSONSerialization.jsonObject(with:$0)} as? [String:Any]
            lastConfig=try configuration.migrate(legacySignature:record?["signature"] as? String)
            applyConfig(lastConfig)
        } catch {configurationNotice=error.localizedDescription}
        if startMonitoring {
            timer=Timer.scheduledTimer(withTimeInterval:15,repeats:true){[weak self] _ in Task{@MainActor in self?.refresh();self?.reminders?.refreshAuthorization()}}
            timer?.tolerance=1
            start()
        }
        statusBar=PulseStatusBar(model:self)
        sidebar=SidebarController(model:self)
        stickyExpansion=StickyExpansionController(model:self)
        reminders=TaskNotificationController(enabled:startMonitoring,openTask:{[weak self] id in self?.openTaskID(id)})
        reminders?.configure(notificationPreferences)
        if startMonitoring {snapshotObserver=SnapshotObserver(directory:PulsePaths.data){[weak self] in self?.refresh()}}
        refresh()
    }
    private func applyConfig(_ config:[String:Any]) {
        lighting=config["lighting"] as? Bool ?? false
        if settingsSave==nil {preferences=LightPreferences(config["lightSettings"] as? [String:Any] ?? [:])}
        menuBarPreferences=MenuBarPreferences(config["menuBarSettings"] as? [String:Any] ?? [:])
        notificationPreferences=NotificationPreferences(config["notificationSettings"] as? [String:Any] ?? [:])
        quotaNotificationPreferences=QuotaNotificationPreferences(config["quotaNotificationSettings"] as? [String:Any] ?? [:])
        reminders?.configure(notificationPreferences)
        selectedDeviceKey=config["selectedDeviceKey"] as? String
        stickyPinned=(config["windowSettings"] as? [String:Any])?["stickyPinned"] as? Bool ?? false
        desktopPreferences=DesktopPreferences(config["windowSettings"] as? [String:Any] ?? [:])
        reminders?.sidebarPreferences=desktopPreferences
        let next=PulseAppearance(rawValue:config["appearance"] as? String ?? "") ?? .system
        appearance=next
        NSApp.appearance=next == .system ? nil:NSAppearance(named:next == .dark ? .darkAqua:.aqua)
        sidebar?.configure(desktopPreferences)
        stickyExpansion?.synchronize(desktopPreferences)
    }
    private func readConfig()->[String:Any] {
        do {lastConfig=try configuration.read();configurationNotice=nil}
        catch {configurationNotice=error.localizedDescription}
        return lastConfig
    }
    @discardableResult private func updateConfig(_ change:(inout [String:Any])->Void)->Bool {
        do {lastConfig=try configuration.update(change);configurationNotice=nil;return true}
        catch {configurationNotice=error.localizedDescription;return false}
    }
    func refresh() {
        snapshot = .read();running=monitoringRequested && (child?.isRunning ?? false)
        readResetReceipt()
        let config=readConfig();applyConfig(config)
        reminders?.consume(snapshot,running:running)
        if let data=try? Data(contentsOf:PulsePaths.data.appendingPathComponent("devices.json")),let inventory=try? JSONDecoder().decode(DeviceInventory.self,from:data) {deviceInventory=inventory}
        statusBar?.update()
        if monitoringAllowed {AmbientInput.shared.configure(inputRequested)}
        if let preview=config["preview"] as? [String:Any],let at=preview["startedAt"] as? Double,
           Date().timeIntervalSince1970-at < (preview["duration"] as? Double ?? 8) {previewScene=preview["scene"] as? String} else {previewScene=nil}
        if monitoringAllowed && Date().timeIntervalSince(lastReload)>300 {WidgetCenter.shared.reloadAllTimelines();lastReload=Date()}
    }
    var resetReady:Bool {
        let confirmedFresh = running && !snapshot.stale && (!((resetResult?.succeeded) ?? false) || snapshot.quotaAt >= (resetResult?.at ?? 0))
        return QuotaResetPolicy.canStart(accountKey:snapshot.accountKey,fresh:confirmedFresh,count:snapshot.resetCredits,busy:resetBusy,result:resetResult)
    }
    var pendingResetID:String? {resetResult?.pendingID(for:snapshot.accountKey)}
    private func readResetReceipt() {
        guard !resetBusy,let key=snapshot.accountKey,QuotaResetPolicy.validAccount(key) else{return}
        if resetResult?.accountKey != key {resetResult=nil}
        let url=PulsePaths.data.appendingPathComponent("quota-reset-"+key+".json")
        if let data=try? Data(contentsOf:url),let candidate=try? JSONDecoder().decode(QuotaResetResult.self,from:data),candidate.accountKey==key,
           candidate.uncertain || candidate.at >= (resetResult?.at ?? 0) {resetResult=candidate}
    }
    func requestQuotaRefresh() {
        guard monitoringAllowed else{return}
        let now=Date().timeIntervalSince1970
        do {
            let data=try JSONSerialization.data(withJSONObject:["at":now])
            try data.write(to:PulsePaths.data.appendingPathComponent("quota-refresh-request.json"),options:.atomic)
            quotaRefreshRequestedAt=now
        } catch {self.error="无法请求刷新额度"}
    }
    func useQuotaReset(accountKey:String,requestID:String) {
        guard !resetBusy else{return}
        func rejected(_ message:String) {resetResult=QuotaResetResult(requestID:requestID,accountKey:accountKey,state:"rejected",outcome:nil,message:message,at:Date().timeIntervalSince1970)}
        guard monitoringAllowed else {rejected("预览模式不会执行真实重置。");return}
        guard accountKey==snapshot.accountKey,resetReady else {rejected("账号或额度状态已变化，请刷新后重新确认。");return}
        if let pendingResetID,pendingResetID != requestID {rejected("请先确认上一次重置操作的结果。");readResetReceipt();return}
        let info=Bundle.main.infoDictionary ?? [:]
        guard let python=info["PulsePython"] as? String,let resources=Bundle.main.resourceURL else {rejected("缺少重置功能的运行配置。");return}
        let process=Process(),output=Pipe()
        process.executableURL=PulseRuntimePaths.resolve(python,resources:resources)
        process.currentDirectoryURL=resources.appendingPathComponent("backend")
        process.arguments=["-B","-m","codex_pulse.quota_reset","--data-dir",PulsePaths.data.path,"--request-id",requestID,"--expected-account-key",accountKey,"--confirmed"]
        process.standardOutput=output;process.standardError=FileHandle.nullDevice
        process.terminationHandler={[weak self] ended in
            let data=output.fileHandleForReading.readDataToEndOfFile()
            let result=try? JSONDecoder().decode(QuotaResetResult.self,from:data)
            Task { @MainActor in
                guard let self,self.resetChild === ended else{return}
                self.resetBusy=false;self.resetChild=nil
                self.resetResult=result ?? QuotaResetResult(requestID:requestID,accountKey:accountKey,state:"unknown",outcome:nil,message:"未取得操作结果，请沿用同一次请求确认。",at:Date().timeIntervalSince1970)
                self.readResetReceipt();self.requestQuotaRefresh()
            }
        }
        do {resetBusy=true;resetChild=process;try process.run()}
        catch {resetBusy=false;resetChild=nil;rejected("重置进程未能启动，未执行重置。");readResetReceipt()}
    }
    func presentWindow(_ id:String,using open:(String)->Void) {
        stickyExpansion?.dismiss()
        if let mode=PulseWindowMode(rawValue:id) {windows.present(mode,open:open)} else {open(id)}
        NSApp.activate(ignoringOtherApps:true)
    }
    func setStickyPinned(_ pinned:Bool) {
        do {lastConfig=try configuration.saveStickyPinned(pinned);stickyPinned=pinned;configurationNotice=nil}
        catch {configurationNotice=error.localizedDescription}
    }
    func saveDesktopSettings(_ changes:[String:Any]) {
        do {lastConfig=try configuration.saveWindowSettings(changes);applyConfig(lastConfig);configurationNotice=nil}
        catch {configurationNotice=error.localizedDescription}
    }
    func setStickySize(_ size:StickySize) {saveDesktopSettings(["stickySize":size.rawValue])}
    func setMiniDiameter(_ value:Double) {saveDesktopSettings(["miniDiameter":MiniRingSizing.normalized(value)])}
    func setMiniClickAction(_ action:MiniRingClickAction) {saveDesktopSettings(["miniClickAction":action.rawValue])}
    func toggleSidebar() {saveDesktopSettings(["sidebarEnabled":!desktopPreferences.sidebarEnabled])}
    func setAppearance(_ next:PulseAppearance) {
        if updateConfig({$0["appearance"]=next.rawValue}) {applyConfig(lastConfig)}
    }
    func selectDevice(_ device:KeyboardDevice) {
        guard !deviceInventory.isStale(),device.selectable,device.isVerified,!device.key.isEmpty else {error="该设备当前不可用于联动，请刷新设备列表。";return}
        guard flushSettings() else{return}
        do {
            lastConfig=try configuration.selectDevice(device.key,defaults:LightPreferences().dictionary)
            applyConfig(lastConfig);configurationNotice=nil;previewScene=nil;error=nil
            if monitoringAllowed {AmbientInput.shared.configure(false)}
        } catch {configurationNotice=error.localizedDescription}
    }
    func rescanDevices() {_=updateConfig{$0["deviceScanRequest"]=Date().timeIntervalSince1970}}
    func openTask(_ task:PulseTask) {
        guard let url=WorkbenchTasks.taskURL(for:task),NSWorkspace.shared.urlForApplication(toOpen:url) != nil else {error="未找到可打开该任务的 Codex 应用。";return}
        if !NSWorkspace.shared.open(url) {error="无法打开 Codex 任务，请检查 Codex 是否已安装。"}
    }
    func openTaskID(_ id:String) {
        openTask(snapshot.tasks.first{$0.id==id} ?? PulseTask(id:id,title:"任务",status:"unknown",at:0))
    }
    func saveNotificationPreferences(_ changes:[String:Any]) {
        if updateConfig({config in
            var values=config["notificationSettings"] as? [String:Any] ?? [:]
            changes.forEach{values[$0.key]=$0.value};config["notificationSettings"]=values
        }) {applyConfig(lastConfig)}
    }
    @discardableResult func saveQuotaNotificationSettings(_ values:[String:Any])->Bool {
        let saved=updateConfig {$0["quotaNotificationSettings"]=values}
        if saved {applyConfig(lastConfig)}
        return saved
    }
    func connectTaskSignals() {
        guard monitoringAllowed,!hookConnectionBusy,let resources=Bundle.main.resourceURL,
              let python=Bundle.main.infoDictionary?["PulsePython"] as? String else{return}
        let child=Process(),output=Pipe()
        child.executableURL=PulseRuntimePaths.resolve(python,resources:resources)
        child.currentDirectoryURL=resources.appendingPathComponent("backend")
        child.arguments=["-B","-m","codex_pulse.attention","--configure","--confirmed","--data-dir",PulsePaths.data.path]
        child.standardOutput=output;child.standardError=FileHandle.nullDevice
        child.terminationHandler={[weak self] process in
            let data=output.fileHandleForReading.readDataToEndOfFile()
            let result=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            let configured=process.terminationStatus==0 && result?["configured"] as? Bool == true
            Task{@MainActor in
                self?.hookConnectionBusy=false;self?.hookChild=nil
                self?.hookNotice=configured ? "已添加提醒连接。请在 Codex 的 Hooks 中审阅并信任，再开始新轮次。":"连接未完成，请检查 Codex 的 hooks.json 配置。"
            }
        }
        do {hookConnectionBusy=true;hookChild=child;try child.run()}
        catch {hookConnectionBusy=false;hookChild=nil;hookNotice="无法启动提醒连接。"}
    }
    func saveLighting(_ enabled:Bool) {
        guard !enabled || (deviceReady && selectedDeviceKey != nil) else {route = .devices;error="请先选择已连接且支持的键盘。";return}
        guard flushSettings() else{return}
        if updateConfig({$0["lighting"]=enabled;$0.removeValue(forKey:"preview")}) {
            lighting=enabled;previewScene=nil
            if monitoringAllowed {AmbientInput.shared.configure(inputRequested)}
        }
    }
    func setMenuBarStyle(_ style:MenuBarIconStyle) {
        var next=menuBarPreferences;next.style=style
        if updateConfig({$0["menuBarSettings"]=next.dictionary}) {menuBarPreferences=next;statusBar?.update()}
    }
    func setPreference<T>(_ path:WritableKeyPath<LightPreferences,T>,_ value:T) {
        preferences[keyPath:path]=value
        preferences.sleepAfterSeconds=max(preferences.sleepAfterSeconds,preferences.idleAfterSeconds+30)
        settingsSave?.invalidate()
        settingsSave=Timer.scheduledTimer(withTimeInterval:0.25,repeats:false){[weak self] _ in Task{@MainActor in self?.flushSettings()}}
    }
    @discardableResult func flushSettings()->Bool {
        settingsSave?.invalidate();settingsSave=nil
        do {
            lastConfig=try configuration.saveLightSettings(preferences.dictionary);configurationNotice=nil
            if monitoringAllowed {AmbientInput.shared.configure(inputRequested)}
            return true
        } catch {
            configurationNotice=error.localizedDescription
            preferences=LightPreferences(lastConfig["lightSettings"] as? [String:Any] ?? [:]);return false
        }
    }
    func setAmbientColor(_ color:Color) {
        guard let rgb=NSColor(color).usingColorSpace(.sRGB) else{return}
        let value=String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
        setPreference(\.otherColor,value)
    }
    func resetLightPreferences(){preferences=LightPreferences();flushSettings()}
    func setStyle(_ count:Int,_ style:RunningStyle) {
        switch count {case 1:setPreference(\.mode1,style.rawValue);case 2:setPreference(\.mode2,style.rawValue);case 3:setPreference(\.mode3,style.rawValue);default:setPreference(\.mode4,style.rawValue)}
    }
    func preview(_ scene:String,taskCount:Int=1) {
        guard running && lightingActive,flushSettings() else{return}
        if updateConfig({$0["preview"]=["scene":scene,"startedAt":Date().timeIntervalSince1970,"taskCount":taskCount,"duration":scene=="running" ? preferences.cycleSeconds+2:scene=="brightness-test" ? 5:8]}) {previewScene=scene}
    }
    func stopPreview(){if updateConfig({$0.removeValue(forKey:"preview")}) {previewScene=nil}}
    func start() {
        guard monitoringAllowed,child?.isRunning != true else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        guard let python = info["PulsePython"] as? String, let resources = Bundle.main.resourceURL else { error = "缺少后台运行配置";return }
        let process = Process()
        process.executableURL = PulseRuntimePaths.resolve(python, resources: resources)
        process.currentDirectoryURL = resources.appendingPathComponent("backend")
        var args = ["-B","-m","codex_pulse.monitor","--parent",String(getpid()),"--data-dir",PulsePaths.data.path]
        if let node = info["PulseNode"] as? String { args += ["--node",PulseRuntimePaths.resolve(node, resources: resources).path] }
        process.arguments = args
        process.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.child === ended else { return }
                self.running = false
                AmbientInput.shared.configure(false)
                if ended.terminationStatus != 0 && ended.terminationReason == .exit {
                    self.error = ended.terminationStatus == 75 ? "监控仍被其他进程占用，请稍后重试；详情见设置的“隐私与诊断”。":"监控后台已退出（代码 \(ended.terminationStatus)），请在设置的“隐私与诊断”中查看日志"
                }
            }
        }
        let log = PulsePaths.data.appendingPathComponent("monitor.log")
        if !FileManager.default.fileExists(atPath:log.path) { FileManager.default.createFile(atPath:log.path,contents:nil) }
        if let handle = try? FileHandle(forWritingTo:log) {
            _ = try? handle.seekToEnd()
            let marker="[\(ISO8601DateFormatter().string(from:Date()))] 启动监控，应用 PID \(getpid())\n"
            try? handle.write(contentsOf:Data(marker.utf8))
            process.standardOutput=handle;process.standardError=handle
        }
        do { try process.run();child=process;monitoringRequested=true;running=true;error=nil }
        catch { self.error = "后台启动失败：\(error.localizedDescription)" }
    }
    func stop(){monitoringRequested=false;running=false;reminders?.dismissAll();AmbientInput.shared.configure(false);flushSettings();stopPreview();child?.terminate()}
    func quit(){stop();NSApp.terminate(nil)}
}

struct Dashboard:View {
    @ObservedObject var model:PulseModel
    var body:some View {WorkbenchShell(model:model).preferredColorScheme(model.appearance.preferredScheme)}
}

@main
struct CodexPulseApp: App {
    @NSApplicationDelegateAdaptor(PulseApplicationDelegate.self) private var appDelegate
    @StateObject private var model = PulseModel()
    var body: some Scene {
        Window("Codex Pulse",id:"dashboard") {
            PulseDashboardWindow(model:model)
                .onAppear {
                    appDelegate.reopen = {
                        model.statusBar?.openWindow?((model.windows.selected ?? .dashboard).rawValue)
                    }
                }
                .onOpenURL { _ in NSApp.activate(ignoringOtherApps:true) }
        }
            .defaultSize(width:1280,height:820)
        Window("Codex Pulse 便签",id:"sticky") {
            StickyDashboard(model:model)
        }.defaultSize(width:344,height:384).windowResizability(.contentSize)
        Window("Codex Pulse 设置",id:"settings") {
            PulseSettings(model:model).preferredColorScheme(model.appearance.preferredScheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing:.appTermination) {Button("退出 Codex Pulse"){model.quit()}.keyboardShortcut("q",modifiers:.command)}
            CommandGroup(after:.windowArrangement) {
                Button("打开便签模式"){model.statusBar?.openWindow?("sticky")}.keyboardShortcut("m",modifiers:[.command,.shift])
                Button(model.desktopPreferences.sidebarEnabled ? "关闭屏幕侧边栏":"开启屏幕侧边栏"){model.toggleSidebar()}
                    .keyboardShortcut("b",modifiers:[.command,.shift])
            }
            CommandGroup(after:.appSettings) {
                Button("设置…") {model.statusBar?.openWindow?("settings")}.keyboardShortcut(",",modifiers:.command)
            }
        }
    }
}

struct PulseDashboardWindow: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: PulseModel
    var body: some View {
        Dashboard(model:model).background(WindowModeRegistration(mode:.dashboard,coordinator:model.windows).allowsHitTesting(false).accessibilityHidden(true)).onAppear {
            model.statusBar?.openWindow = { id in model.presentWindow(id,using:{openWindow(id:$0)}) }
            model.sidebar?.start()
        }
    }
}

@MainActor
final class PulseStatusBar: NSObject {
    private weak var model: PulseModel?
    private let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
    var openWindow: ((String)->Void)?
    init(model: PulseModel) {
        self.model=model
        super.init()
        item.button?.target=self
        item.button?.action=#selector(showMenu)
        item.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        update()
    }
    func update() {
        guard let model else { return }
        let quota=MenuBarQuota(remaining:model.snapshot.primary?.remaining,stale:model.snapshot.stale)
        item.button?.image=MenuBarIcon.image(style:model.menuBarPreferences.style,quota:quota)
        item.button?.toolTip="Codex Pulse · "+quota.summary
        item.button?.setAccessibilityLabel("Codex Pulse · "+quota.summary)
    }
    @objc private func showMenu() {
        guard let model else { return }
        let menu=NSMenu()
        func add(_ title:String,_ action:Selector) {
            let entry=NSMenuItem(title:title,action:action,keyEquivalent:"")
            entry.target=self;menu.addItem(entry)
        }
        add("打开 Codex Pulse",#selector(showDashboard))
        add("打开便签模式",#selector(showSticky))
        add(model.desktopPreferences.sidebarEnabled ? "关闭屏幕侧边栏":"开启屏幕侧边栏",#selector(toggleSidebar))
        let quota=MenuBarQuota(remaining:model.snapshot.primary?.remaining,stale:model.snapshot.stale)
        let status=NSMenuItem(title:quota.summary,action:nil,keyEquivalent:"");status.isEnabled=false;menu.addItem(status)
        menu.addItem(.separator())
        add("打开 Tibo 的推特（X）",#selector(openTibo))
        add("OpenAI 服务状态",#selector(openOpenAIStatus))
        add("设置…",#selector(showSettings))
        add(model.lighting ? "关闭键盘状态灯":"开启键盘状态灯",#selector(toggleLighting))
        menu.addItem(.separator())
        add("隐藏 Codex Pulse",#selector(hideApplication))
        add("退出",#selector(quit))
        // Route both mouse buttons through the native status-item menu.
        item.menu=menu
        item.button?.performClick(nil)
        item.menu=nil
    }
    @objc private func hideApplication(){NSApp.hide(nil)}
    @objc private func showSticky(){openWindow?("sticky")}
    @objc private func toggleSidebar(){model?.toggleSidebar()}
    @objc private func showDashboard() { openWindow?("dashboard") }
    @objc private func showSettings() { openWindow?("settings") }
    @objc private func openTibo() {
        if !NSWorkspace.shared.open(URL(string:"https://x.com/thsottiaux")!) {
            model?.error="无法打开浏览器，请检查默认浏览器设置"
            openWindow?("dashboard")
        }
    }
    @objc private func openOpenAIStatus() {
        if !NSWorkspace.shared.open(URL(string:"https://status.openai.com")!) {
            model?.error="无法打开浏览器，请检查默认浏览器设置";openWindow?("dashboard")
        }
    }
    @objc private func toggleLighting() { if let model { model.saveLighting(!model.lighting) } }
    @objc private func quit() { model?.quit() }
}

struct InputAttentionNotice:View {
    @ObservedObject var model:PulseModel
    @ObservedObject private var input=AmbientInput.shared
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        if model.running && model.lighting && model.preferences.ambientEnabled && model.preferences.ambientInputEnabled &&
            ["permission_required","signature_changed_denied","listener_failed"].contains(input.assessment.code) {
            HStack {
                Label("按键交互需要处理",systemImage:"exclamationmark.triangle").foregroundStyle(.orange)
                Spacer()
                Button("查看设置") {model.settingsCategory = .input;openWindow(id:"settings")}
                    .buttonStyle(.bordered).controlSize(.small)
            }
            .font(.callout)
            .padding(.horizontal,14).padding(.vertical,10)
            .background(Color.orange.opacity(0.08),in:RoundedRectangle(cornerRadius:9))
            .padding(.top,24)
        }
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general="通用与外观", desktop="便签与侧边栏", input="隐私与诊断", widgets="小组件"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .desktop: return "sidebar.right"
        case .input: return "checkmark.shield"
        case .widgets: return "square.grid.2x2"
        }
    }
}

struct PulseSettings: View {
    @AppStorage("showInDock") private var showInDock=true
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: PulseModel
    private var category:SettingsCategory {model.settingsCategory}
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                Text("设置").font(.title2.bold()).padding(.bottom,18)
                ForEach(SettingsCategory.allCases) { item in
                    Button { model.settingsCategory=item } label: {
                        Label(item.rawValue,systemImage:item.icon)
                            .frame(maxWidth:.infinity,alignment:.leading).padding(10)
                            .background(category == item ? pulseMint.opacity(0.15):.clear,in:RoundedRectangle(cornerRadius:8))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(category == item ? .isSelected:[])
                }
                Spacer()
            }.padding(20).frame(width:185)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    Text(category.rawValue).font(.title2.bold())
                    switch category {
                    case .general: generalSettings
                    case .desktop: DesktopSurfaceSettings(model:model)
                    case .input: diagnosticSettings
                    case .widgets: widgetSettings
                    }
                }.padding(26).frame(maxWidth:.infinity,alignment:.leading)
            }
        }.frame(width:820,height:700)
            .preferredColorScheme(model.appearance.preferredScheme)
            .onAppear {
                model.statusBar?.openWindow = { id in model.presentWindow(id,using:{openWindow(id:$0)}) }
                model.sidebar?.start()
            }
    }
    private var generalSettings: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Dock 与菜单栏").font(.headline)
            Toggle("在 Dock 中显示",isOn:$showInDock)
                .onChange(of:showInDock) { _,visible in PulseApplicationDelegate.applyDockVisibility(visible) }
                .help("关闭后仍可从菜单栏打开窗口，后台监控继续运行。")
            Divider()
            Text("应用外观").font(.headline)
            Picker("配色",selection:Binding(get:{model.appearance},set:{model.setAppearance($0)})) {
                ForEach(PulseAppearance.allCases) {Text($0.title).tag($0)}
            }.pickerStyle(.segmented)
            Divider()
            HStack {
                Text("菜单栏外观").font(.headline)
                PulseInfo(title:"菜单栏外观",message:"半环表示主额度窗口中的最低剩余值；数据待更新时显示虚线。")
            }
            ForEach(MenuBarIconStyle.allCases,id:\.rawValue) { style in
                Button { model.setMenuBarStyle(style) } label: {
                    HStack(spacing:14) {
                        Image(nsImage:MenuBarIcon.image(style:style,quota:MenuBarQuota(remaining:65,stale:false))).frame(width:30)
                        Text(style.title)
                        Spacer()
                        Image(systemName:model.menuBarPreferences.style == style ? "checkmark.circle.fill":"circle")
                            .foregroundStyle(model.menuBarPreferences.style == style ? pulseMint:.secondary)
                    }.padding(12).background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:9))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(model.menuBarPreferences.style == style ? .isSelected:[])
            }
            Divider()
            HStack {
                Text("后台监控").font(.headline)
                PulseInfo(title:"后台监控",message:"运行任务时每 15 秒读取额度，空闲时每 120 秒读取；任务变化与手动刷新会触发补读。关闭窗口后继续运行，退出应用后停止。")
            }
            HStack {
                Label(model.running ? "监控运行中":"监控已暂停",systemImage:"waveform.path")
                Spacer()
                Button(model.running ? "暂停监控":"启动监控") { model.running ? model.stop():model.start() }
            }
            if let reminders=model.reminders {Divider();TaskReminderSettings(model:model,reminders:reminders)}
            Divider()
            QuotaNotificationSettings(model:model)
        }
    }
    private var diagnosticSettings:some View {
        VStack(alignment:.leading,spacing:20) {
            GroupBox("普通按键响应") {
                VStack(alignment:.leading,spacing:12) {
                    Toggle("响应普通键盘输入",isOn:Binding(get:{model.preferences.ambientInputEnabled},set:{model.setPreference(\.ambientInputEnabled,$0)}))
                        .help("同时开启键盘联动和交互预设后才会监听；只接收物理按键位置，不读取输入文字。")
                    InputAuthorizationView()
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox("服务状态") {
                VStack(alignment:.leading,spacing:12) {
                    LabeledContent("后台监控",value:model.running ? "运行中":"已暂停")
                    LabeledContent("键盘连接",value:model.snapshot.keyboard.message)
                    if let error=model.error {Text(error).foregroundStyle(.orange)}
                    if let error=model.snapshot.taskError {Text(error).foregroundStyle(.orange)}
                    if let error=model.snapshot.quotaError {Text(error).foregroundStyle(.orange)}
                    Button("查看监控日志") {NSWorkspace.shared.open(PulsePaths.data.appendingPathComponent("monitor.log"))}
                }.font(.callout).padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox("本机数据") {
                VStack(alignment:.leading,spacing:12) {
                    LabeledContent("会话范围",value:"最近 30 个未归档会话")
                    LabeledContent("记录内容",value:"会话元数据；不保存正文或登录令牌")
                    LabeledContent("历史保留",value:"30 天")
                }.font(.callout).padding(12).frame(maxWidth:.infinity,alignment:.leading)
            }
        }
    }
    private var widgetSettings: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("添加桌面／通知中心小组件").font(.headline)
            Text("右键桌面 → 编辑小组件 → 搜索 Codex Pulse。")
            Button("刷新小组件") { model.refresh();WidgetCenter.shared.reloadAllTimelines() }
            Text("小组件由 macOS 安排刷新，可能有延迟。").font(.caption).foregroundStyle(.secondary)
        }.font(.callout)
    }
}

struct LightingPanel: View {
    @ObservedObject var model: PulseModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Toggle("启用键盘联动",isOn:Binding(get:{model.lighting},set:{model.saveLighting($0)})).toggleStyle(.switch)
                Spacer()
            }
            Text(model.snapshot.keyboard.message).font(.caption).foregroundStyle(.secondary)
            AnimatedKeyboardDiagram(expectedDeviceKey:model.selectedDeviceKey,enabled:model.lightingActive)
            VStack(alignment:.leading,spacing:10) {
                Text("按任务数量选择风格").font(.headline)
                ForEach(1...4,id:\.self) { count in
                    HStack {
                        Text(count==4 ? "4 个及以上":"\(count) 个任务").frame(width:84,alignment:.leading)
                        Picker("风格",selection:Binding(get:{model.preferences.style(count)},set:{model.setStyle(count,$0)})) {
                            ForEach(RunningStyle.allCases) { style in Text(style.title(count)).tag(style) }
                        }.labelsHidden().accessibilityLabel(count == 4 ? "4 个及以上任务的风格":"\(count) 个任务的风格")
                            .help(model.preferences.style(count).detail).frame(maxWidth:.infinity)
                        Button("演示") { model.preview("running",taskCount:count) }.disabled(!model.running || !model.lightingActive)
                    }
                }
            }
            Divider()
                    HStack { Text("运行一轮时长").font(.headline);Spacer();Text("约 \(model.preferences.cycleSeconds,specifier:"%.0f") 秒").monospacedDigit() }
                    Slider(value:Binding(get:{model.preferences.cycleSeconds},set:{model.setPreference(\.cycleSeconds,$0)}),in:2...30,step:1).accessibilityLabel("运行一轮时长")
                    HStack { Text("2 秒 · 更快");Spacer();Text("30 秒 · 更慢") }.font(.caption).foregroundStyle(.secondary)
                    Toggle("低额度时 Logo 红色常亮",isOn:Binding(get:{model.preferences.lowAlertEnabled},set:{model.setPreference(\.lowAlertEnabled,$0)}))
                        .help("低额度阈值为 25%。关闭后仅熄灭低额度红灯，重置提示仍保留。")
            HStack(spacing:8) {
                Text("状态演示").font(.caption).foregroundStyle(.secondary)
                ForEach(["completed","reset","low"],id:\.self) { scene in
                    Button(["completed":"轮次结束","reset":"重置","low":"低额度"][scene]!) { model.preview(scene) }
                        .disabled(!model.running || !model.lightingActive)
                }
                if model.previewScene != nil { Button("结束演示") { model.stopPreview() } }
            }.controlSize(.small)
            if model.previewScene != nil {
                Text("正在演示 · 结束后恢复实时状态").font(.caption).foregroundStyle(.cyan)
            }
        }
    }
}

struct LightSettingsSheet: View {
    @ObservedObject var model: PulseModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var hexInput="#FFC284"
    @State private var hexError=false
    @State private var confirmReset=false
    private func binding(_ path: WritableKeyPath<LightPreferences,Double>)->Binding<Double> {
        Binding(get:{model.preferences[keyPath:path]},set:{model.setPreference(path,$0)})
    }
    private func brightness(_ title: String,_ path: WritableKeyPath<LightPreferences,Double>)->some View {
        HStack(spacing:12) {
            Text(title).font(.callout).frame(width:105,alignment:.leading)
            Slider(value:binding(path),in:0...1,step:0.01).accessibilityLabel(title)
            Text("\(model.preferences[keyPath:path]*100,specifier:"%.0f")%").font(.callout).monospacedDigit().frame(width:42,alignment:.trailing)
        }
    }
    private func applyHexColor() {
        guard hexInput.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil else {
            hexError=true
            return
        }
        hexError=false
        model.setPreference(\.otherColor,hexInput.uppercased())
    }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if !embedded {
                HStack { Text("灯光设置").font(.title2.bold());Spacer();Button("完成"){model.flushSettings();dismiss()}.keyboardShortcut(.defaultAction) }
            }
            Group {
                VStack(alignment:.leading,spacing:15) {
                    HStack {
                        Text("亮度").font(.headline)
                        PulseInfo(title:"亮度",message:"实际亮度为全局亮度乘以分区亮度；设为 0% 会关闭该区域。")
                    }
                    brightness("全局亮度",\.globalBrightness)
                    Divider()
                    Text("功能区").font(.headline)
                    brightness("F1–F10 额度条",\.quotaBrightness)
                    brightness("左上角 Logo",\.logoBrightness)
                    brightness("右侧小键盘",\.keypadBrightness)
                    Divider()
                    Text("非功能区").font(.headline)
                    brightness("其他按键亮度",\.otherBrightness)
                    Toggle("自定义其他区域颜色",isOn:Binding(get:{model.preferences.otherColorEnabled},set:{model.setPreference(\.otherColorEnabled,$0)}))
                    HStack {
                        ColorPicker("颜色",selection:Binding(get:{model.preferences.ambientColor},set:{model.setAmbientColor($0)}),supportsOpacity:false)
                        TextField("#RRGGBB",text:$hexInput).font(.system(.body,design:.monospaced)).frame(width:96)
                            .accessibilityLabel("颜色十六进制值")
                            .onSubmit {applyHexColor()}
                            .onChange(of:hexInput) {_,_ in hexError=false}
                        Button("应用颜色") {applyHexColor()}
                    }.disabled(!model.preferences.otherColorEnabled || model.preferences.ambientEnabled)
                    if hexError {Text("请输入 #RRGGBB 格式的颜色。").font(.caption).foregroundStyle(.orange)}
                    if model.preferences.ambientEnabled && model.preferences.otherColorEnabled {
                        Text("预设启用时，自定义颜色暂不生效。").font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                    Text("空闲降亮与休眠").font(.headline)
                    Stepper(value:binding(\.idleAfterSeconds),in:30...1800,step:30) {
                        HStack { Text("空闲多久后降亮");Spacer();Text("\(model.preferences.idleAfterSeconds,specifier:"%.0f") 秒").monospacedDigit() }
                    }.accessibilityLabel("空闲降亮延时")
                    brightness("降亮后的亮度",\.idleBrightness)
                    Stepper(value:binding(\.sleepAfterSeconds),in:60...7200,step:30) {
                        HStack { Text("空闲多久后休眠");Spacer();Text("\(model.preferences.sleepAfterSeconds/60,specifier:"%.1f") 分钟").monospacedDigit() }
                    }.accessibilityLabel("空闲休眠延时")
                    Button("显示 5 秒满亮白光（自检）") { model.preview("brightness-test") }
                        .disabled(!model.running || !model.lightingActive)
                        .help("自检会唤醒灯光，5 秒后恢复原颜色与动画。")
                }.padding(.trailing,4)
            }
            HStack { Button("恢复全部灯光默认设置…"){confirmReset=true};Spacer();Text(model.deviceReady && model.lighting ? "自动保存 · 等待设备应用":"自动保存 · 设备连接后应用").font(.caption).foregroundStyle(.secondary) }
        }.padding(embedded ? 0:24).frame(maxWidth:.infinity).preferredColorScheme(model.appearance.preferredScheme)
            .confirmationDialog("恢复全部灯光默认设置？",isPresented:$confirmReset) {
                Button("恢复默认设置",role:.destructive){model.resetLightPreferences()}
                Button("取消",role:.cancel){}
            } message: {Text("任务风格、亮度、省电和非功能区预设将恢复默认值；灯光总开关保持不变。")}
            .onAppear { hexInput=model.preferences.otherColor }
            .onChange(of:model.preferences.otherColor) { _,value in hexInput=value }
    }
}
