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
    @Published var lighting=false
    @Published var previewScene:String?
    @Published var preferences=LightPreferences()
    @Published var menuBarPreferences=MenuBarPreferences()
    @Published var error:String?
    @Published var configurationNotice:String?
    @Published var settingsCategory:SettingsCategory = .general
    @Published var route:WorkbenchRoute = .overview
    @Published var appearance:PulseAppearance = .system
    @Published var stickyPinned=false
    @Published var deviceInventory=DeviceInventory.empty
    @Published var selectedDeviceKey:String?
    let windows=PulseWindowCoordinator()
    private(set) var statusBar:PulseStatusBar?
    private var child:Process?
    private var timer:Timer?
    private var lastReload=Date.distantPast
    private var settingsSave:Timer?
    private let configuration=PulseConfigurationStore(directory:PulsePaths.data)
    private var lastConfig:[String:Any]=[:]
    private var monitoringAllowed=true
    private var monitoringRequested=false

    var selectedDevice:KeyboardDevice? {deviceInventory.devices.first{$0.key==selectedDeviceKey}}
    var deviceReady:Bool { deviceInventory.status == "ready" && !deviceInventory.isStale() && selectedDevice?.selectable==true && selectedDevice?.isVerified==true }
    var lightingActive:Bool {lighting && deviceReady && deviceInventory.activeKey==selectedDeviceKey && snapshot.keyboard.status=="connected" && Date().timeIntervalSince1970-snapshot.generatedAt<30}
    var inputRequested:Bool {running && lighting && deviceReady && deviceInventory.activeKey==selectedDeviceKey && preferences.ambientEnabled && preferences.ambientInputEnabled && AmbientCatalog.shared.presets.first{$0.id==preferences.ambientPreset}?.category == "reactive"}

    init(startMonitoring:Bool=true) {
        monitoringAllowed=startMonitoring
        do {
            let backup=PulsePaths.data.appendingPathComponent("keyboard-backup.json")
            let record=(try? Data(contentsOf:backup)).flatMap{try? JSONSerialization.jsonObject(with:$0)} as? [String:Any]
            lastConfig=try configuration.migrate(legacySignature:record?["signature"] as? String)
            applyConfig(lastConfig)
        } catch {configurationNotice=error.localizedDescription}
        timer=Timer.scheduledTimer(withTimeInterval:5,repeats:true){[weak self] _ in Task{@MainActor in self?.refresh()}}
        timer?.tolerance=1
        if startMonitoring {start()}
        statusBar=PulseStatusBar(model:self)
        refresh()
    }
    private func applyConfig(_ config:[String:Any]) {
        lighting=config["lighting"] as? Bool ?? false
        if settingsSave==nil {preferences=LightPreferences(config["lightSettings"] as? [String:Any] ?? [:])}
        menuBarPreferences=MenuBarPreferences(config["menuBarSettings"] as? [String:Any] ?? [:])
        selectedDeviceKey=config["selectedDeviceKey"] as? String
        stickyPinned=(config["windowSettings"] as? [String:Any])?["stickyPinned"] as? Bool ?? false
        let next=PulseAppearance(rawValue:config["appearance"] as? String ?? "") ?? .system
        appearance=next
        NSApp.appearance=next == .system ? nil:NSAppearance(named:next == .dark ? .darkAqua:.aqua)
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
        let config=readConfig();applyConfig(config)
        if let data=try? Data(contentsOf:PulsePaths.data.appendingPathComponent("devices.json")),let inventory=try? JSONDecoder().decode(DeviceInventory.self,from:data) {deviceInventory=inventory}
        statusBar?.update()
        if monitoringAllowed {AmbientInput.shared.configure(inputRequested)}
        if let preview=config["preview"] as? [String:Any],let at=preview["startedAt"] as? Double,
           Date().timeIntervalSince1970-at < (preview["duration"] as? Double ?? 8) {previewScene=preview["scene"] as? String} else {previewScene=nil}
        if monitoringAllowed && Date().timeIntervalSince(lastReload)>300 {WidgetCenter.shared.reloadAllTimelines();lastReload=Date()}
    }
    func presentWindow(_ id:String,using open:(String)->Void) {
        if let mode=PulseWindowMode(rawValue:id) {windows.present(mode,open:open)} else {open(id)}
        NSApp.activate(ignoringOtherApps:true)
    }
    func setStickyPinned(_ pinned:Bool) {
        do {lastConfig=try configuration.saveStickyPinned(pinned);stickyPinned=pinned;configurationNotice=nil}
        catch {configurationNotice=error.localizedDescription}
    }
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
    func stop(){monitoringRequested=false;running=false;AmbientInput.shared.configure(false);flushSettings();stopPreview();child?.terminate()}
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
        }.defaultSize(width:344,height:344).windowResizability(.contentSize)
        Window("Codex Pulse 设置",id:"settings") {
            PulseSettings(model:model).preferredColorScheme(model.appearance.preferredScheme)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing:.appTermination) {Button("退出 Codex Pulse"){model.quit()}.keyboardShortcut("q",modifiers:.command)}
            CommandGroup(after:.windowArrangement) {
                Button("打开便签模式"){model.statusBar?.openWindow?("sticky")}.keyboardShortcut("m",modifiers:[.command,.shift])
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
        let quota=MenuBarQuota(remaining:model.snapshot.primary?.remaining,stale:model.snapshot.stale)
        let status=NSMenuItem(title:quota.summary,action:nil,keyEquivalent:"");status.isEnabled=false;menu.addItem(status)
        menu.addItem(.separator())
        add("打开 Tibo 的推特（X）",#selector(openTibo))
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
    @objc private func showDashboard() { openWindow?("dashboard") }
    @objc private func showSettings() { openWindow?("settings") }
    @objc private func openTibo() {
        if !NSWorkspace.shared.open(URL(string:"https://x.com/thsottiaux")!) {
            model?.error="无法打开浏览器，请检查默认浏览器设置"
            openWindow?("dashboard")
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
    case general="通用与外观", input="隐私与诊断", widgets="小组件与说明"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .input: return "checkmark.shield"
        case .widgets: return "square.grid.2x2"
        }
    }
    var detail:String {
        switch self {
        case .general:return "管理菜单栏外观与后台监控。"
        case .input:return "检查普通按键响应、输入权限与服务状态。"
        case .widgets:return "添加小组件，了解数据范围与刷新方式。"
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
                Text("设置自动保存").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(width:185)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(alignment:.leading,spacing:7) {
                        Text(category.rawValue).font(.title2.bold())
                        Text(category.detail).font(.callout).foregroundStyle(.secondary)
                    }
                    switch category {
                    case .general: generalSettings
                    case .input: diagnosticSettings
                    case .widgets: widgetSettings
                    }
                }.padding(26).frame(maxWidth:.infinity,alignment:.leading)
            }
        }.frame(width:820,height:700)
            .preferredColorScheme(model.appearance.preferredScheme)
            .onAppear {
                model.statusBar?.openWindow = { id in model.presentWindow(id,using:{openWindow(id:$0)}) }
            }
    }
    private var generalSettings: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("Dock 与菜单栏").font(.headline)
            Toggle("在 Dock 中显示",isOn:$showInDock)
                .onChange(of:showInDock) { _,visible in PulseApplicationDelegate.applyDockVisibility(visible) }
            Text("关闭后隐藏 Dock 图标，仍可从菜单栏打开窗口和设置，后台监控继续运行。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("应用外观").font(.headline)
            Picker("配色",selection:Binding(get:{model.appearance},set:{model.setAppearance($0)})) {
                ForEach(PulseAppearance.allCases) {Text($0.title).tag($0)}
            }.pickerStyle(.segmented)
            Text("跟随系统会随 macOS 外观自动切换。主题只改变界面，不改变键盘配色。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("菜单栏外观").font(.headline)
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
            }
            Text("半环表示主额度窗口中的最低剩余值；数据待更新时显示虚线。选择后自动保存。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("后台监控").font(.headline)
            HStack {
                Label(model.running ? "监控运行中":"监控已暂停",systemImage:"waveform.path")
                Spacer()
                Button(model.running ? "暂停监控":"启动监控") { model.running ? model.stop():model.start() }
            }
            Text("每 60 秒读取额度，每 5 秒更新本机任务。关闭窗口后继续运行，退出 App 后停止。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var diagnosticSettings:some View {
        VStack(alignment:.leading,spacing:20) {
            GroupBox("普通按键响应") {
                VStack(alignment:.leading,spacing:12) {
                    Toggle("响应普通键盘输入",isOn:Binding(get:{model.preferences.ambientInputEnabled},set:{model.setPreference(\.ambientInputEnabled,$0)}))
                    Text("同时开启状态灯光和交互预设后才会监听；只接收物理按键位置，不读取输入文字。").font(.caption).foregroundStyle(.secondary)
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
        }
    }
    private var widgetSettings: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("添加桌面／通知中心小组件").font(.headline)
            Text("右键桌面 → 编辑小组件 → 搜索 Codex Pulse → 选择尺寸。大尺寸显示最近任务与额度趋势。")
            Button("刷新小组件") { model.refresh();WidgetCenter.shared.reloadAllTimelines() }
            Text("小组件由 macOS 安排刷新，可能有延迟；实时状态请查看主窗口。").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("数据与隐私").font(.headline)
            Text("仅监测本机最近 30 个未归档会话，历史保留 30 天。不会保存会话正文或登录令牌。轮次结束不代表任务目标已验收。")
            Text("消耗速度按最近一小时连续样本估算，至少需要五分钟；预测不代表承诺。").font(.caption).foregroundStyle(.secondary)
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
                        }.labelsHidden().frame(maxWidth:.infinity)
                        Button("演示") { model.preview("running",taskCount:count) }.disabled(!model.running || !model.lightingActive)
                    }
                    Text(model.preferences.style(count).detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Divider()
                    HStack { Text("运行一轮时长").font(.headline);Spacer();Text("约 \(model.preferences.cycleSeconds,specifier:"%.0f") 秒").monospacedDigit() }
                    Slider(value:Binding(get:{model.preferences.cycleSeconds},set:{model.setPreference(\.cycleSeconds,$0)}),in:2...30,step:1).accessibilityLabel("运行一轮时长")
                    HStack { Text("2 秒 · 更快");Spacer();Text("30 秒 · 更慢") }.font(.caption).foregroundStyle(.secondary)
                    Toggle("低额度时 Logo 红色常亮",isOn:Binding(get:{model.preferences.lowAlertEnabled},set:{model.setPreference(\.lowAlertEnabled,$0)}))
                    Text("低额度阈值为 25%。关闭后仅熄灭低额度红灯，重置提示仍保留。").font(.caption).foregroundStyle(.secondary)
            HStack(spacing:8) {
                Text("状态演示").font(.caption).foregroundStyle(.secondary)
                ForEach(["completed","reset","low"],id:\.self) { scene in
                    Button(["completed":"轮次结束","reset":"重置","low":"低额度"][scene]!) { model.preview(scene) }
                        .disabled(!model.running || !model.lightingActive)
                }
                if model.previewScene != nil { Button("结束演示") { model.stopPreview() } }
            }.controlSize(.small)
            Text(model.previewScene != nil ? "正在演示；播放后自动返回实时状态，额度与任务记录不受影响。":"运行演示会展示完整一轮。关闭状态灯后，G HUB 继续原来的配色或动画。")
                .font(.caption2).foregroundStyle(model.previewScene != nil ? .cyan:.secondary)
        }
    }
}

struct LightSettingsSheet: View {
    @ObservedObject var model: PulseModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var hexInput="#FFC284"
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
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if !embedded {
                HStack { Text("灯光设置").font(.title2.bold());Spacer();Button("完成"){model.flushSettings();dismiss()}.keyboardShortcut(.defaultAction) }
            }
            Group {
                VStack(alignment:.leading,spacing:15) {
                    brightness("全局亮度",\.globalBrightness)
                    Text("实际亮度 = 全局 × 分区；设为 0% 即关闭该区域。").font(.caption).foregroundStyle(.secondary)
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
                            .onSubmit {
                                if hexInput.range(of:"^#[0-9A-Fa-f]{6}$",options:.regularExpression) != nil { model.setPreference(\.otherColor,hexInput.uppercased()) }
                                else { hexInput=model.preferences.otherColor }
                            }
                    }.disabled(!model.preferences.otherColorEnabled || model.preferences.ambientEnabled)
                    Text("包含 G1–G5、主键区、导航键、F11/F12。启用预设时，原统一颜色暂不生效；关闭预设后恢复原配色。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Divider()
                    Text("空闲降亮与休眠").font(.headline)
                    Stepper(value:binding(\.idleAfterSeconds),in:30...1800,step:30) {
                        HStack { Text("空闲多久后降亮");Spacer();Text("\(model.preferences.idleAfterSeconds,specifier:"%.0f") 秒").monospacedDigit() }
                    }.accessibilityLabel("空闲降亮延时")
                    brightness("降亮后的亮度",\.idleBrightness)
                    Stepper(value:binding(\.sleepAfterSeconds),in:60...7200,step:30) {
                        HStack { Text("空闲多久后休眠");Spacer();Text("\(model.preferences.sleepAfterSeconds/60,specifier:"%.1f") 分钟").monospacedDigit() }
                    }.accessibilityLabel("空闲休眠延时")
                    Text("降亮延时 30 秒–30 分钟，目标亮度 0–100%；休眠 1–120 分钟，并始终晚于降亮。省电由键盘执行，不在动画里再叠乘一次。").font(.caption).foregroundStyle(.secondary)
                    Button("显示 5 秒满亮白光（自检）") { model.preview("brightness-test") }
                        .disabled(!model.running || !model.lightingActive)
                    Text("暂时用白光对比实际亮度，5 秒后恢复原颜色与动画。自检会唤醒灯光。").font(.caption).foregroundStyle(.secondary)
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
